package com.example.note_secret_search.security

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal class MigrationFileCoordinatorTest {
    private val files = FakeMigrationFileSetAccess().apply {
        put(MigrationFileSlot.ACTIVE, "legacy-database")
    }
    private val journal = FakeMigrationJournalStore()
    private val coordinator = MigrationFileCoordinator(
        files = files,
        journalStore = journal,
    )

    @Test
    fun `migration advances durably through all file stages`() {
        val keyId = "123e4567-e89b-42d3-a456-426614174000"

        assertEquals(MigrationJournalStage.DETECTED, coordinator.detect().stage)
        coordinator.markKeyringReady(keyId)
        val backup = coordinator.prepareBackup(keyId)

        assertEquals(MigrationJournalStage.BACKUP_READY, backup.stage)
        assertEquals(files.digest(MigrationFileSlot.ACTIVE), backup.sourceDigest)
        assertEquals(
            files.digest(MigrationFileSlot.ACTIVE),
            files.digest(MigrationFileSlot.BACKUP),
        )

        coordinator.preparePending(keyId)
        files.put(MigrationFileSlot.PENDING, "schema-v4-database")
        coordinator.markRowsCopied(keyId)
        val validated = coordinator.markValidated(keyId)
        val activated = coordinator.activate(keyId)
        val postSwap = coordinator.markPostSwapValidated(keyId)

        assertEquals(MigrationJournalStage.VALIDATED, validated.stage)
        assertEquals(MigrationJournalStage.NEW_ACTIVATED, activated.stage)
        assertEquals(MigrationJournalStage.POST_SWAP_VALIDATED, postSwap.stage)
        assertEquals(
            files.digest(MigrationFileSlot.ACTIVE),
            postSwap.activeDigest,
        )
        assertFalse(
            coordinator.isCleanupComplete(
                keyId,
                checkNotNull(postSwap.activeDigest),
            ),
        )

        val cleanup = coordinator.cleanup(keyId)

        assertEquals(MigrationJournalStage.CLEANUP_COMPLETE, cleanup.stage)
        assertFalse(files.exists(MigrationFileSlot.BACKUP))
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
        assertTrue(
            coordinator.isCleanupComplete(
                keyId,
                checkNotNull(cleanup.activeDigest),
            ),
        )

        coordinator.finish(keyId)

        assertNull(journal.value)
    }

    @Test
    fun `backup refuses insufficient free space without copying source`() {
        files.available = (64L * 1024 * 1024) +
            (2L * files.sizeBytes(MigrationFileSlot.ACTIVE)) - 1L
        val keyId = "123e4567-e89b-42d3-a456-426614174000"
        coordinator.detect()
        coordinator.markKeyringReady(keyId)

        val error = captureSecurityError {
            coordinator.prepareBackup(keyId)
        }

        assertEquals(
            NativeSecurityErrorCode.MIGRATION_STORAGE_INSUFFICIENT,
            error.code,
        )
        assertEquals(MigrationJournalStage.KEYRING_READY, journal.value?.stage)
        assertFalse(files.exists(MigrationFileSlot.BACKUP))
    }

    @Test
    fun `backup refuses an uncheckpointed source file set`() {
        val keyId = "123e4567-e89b-42d3-a456-426614174000"
        coordinator.detect()
        coordinator.markKeyringReady(keyId)
        files.sidecarSlots += MigrationFileSlot.ACTIVE

        val error = captureSecurityError {
            coordinator.prepareBackup(keyId)
        }

        assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
        assertEquals(MigrationJournalStage.KEYRING_READY, journal.value?.stage)
        assertFalse(files.exists(MigrationFileSlot.BACKUP))
    }

    @Test
    fun `activation resumes forward after interruption at old moved`() {
        val keyId = prepareValidatedPending()
        files.failMoveToActive = true

        captureSecurityError { coordinator.activate(keyId) }

        assertEquals(MigrationJournalStage.OLD_MOVED, journal.value?.stage)
        assertTrue(files.exists(MigrationFileSlot.ROLLBACK))
        assertTrue(files.exists(MigrationFileSlot.PENDING))
        assertFalse(files.exists(MigrationFileSlot.ACTIVE))

        files.failMoveToActive = false
        val resumed = coordinator.activate(keyId)

        assertEquals(MigrationJournalStage.NEW_ACTIVATED, resumed.stage)
        assertEquals(
            resumed.pendingDigest,
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertFalse(files.exists(MigrationFileSlot.PENDING))
    }

    @Test
    fun `activation resumes when old moved journal write is interrupted`() {
        val keyId = prepareValidatedPending()
        journal.failOnceOnStage = MigrationJournalStage.OLD_MOVED

        captureSecurityError { coordinator.activate(keyId) }

        assertEquals(MigrationJournalStage.VALIDATED, journal.value?.stage)
        assertTrue(files.exists(MigrationFileSlot.ROLLBACK))
        assertTrue(files.exists(MigrationFileSlot.PENDING))
        assertFalse(files.exists(MigrationFileSlot.ACTIVE))

        val resumed = MigrationFileCoordinator(
            files = files,
            journalStore = journal,
        ).activate(keyId)

        assertEquals(MigrationJournalStage.NEW_ACTIVATED, resumed.stage)
        assertEquals(
            resumed.pendingDigest,
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertFalse(files.exists(MigrationFileSlot.PENDING))
    }

    @Test
    fun `corrupt pending at old moved restores rollback for a retry`() {
        val keyId = prepareValidatedPending()
        files.failMoveToActive = true
        captureSecurityError { coordinator.activate(keyId) }
        files.failMoveToActive = false
        files.put(MigrationFileSlot.PENDING, "corrupt-pending-database")

        val recovered = coordinator.inspect()

        assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
        assertEquals(
            files.digest(MigrationFileSlot.BACKUP),
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
        assertFalse(files.exists(MigrationFileSlot.PENDING))
    }

    @Test
    fun `corrupt activated database restores rollback for a retry`() {
        val keyId = prepareValidatedPending()
        coordinator.activate(keyId)
        files.put(MigrationFileSlot.ACTIVE, "corrupt-activated-database")

        val recovered = coordinator.inspect()

        assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
        assertEquals(
            files.digest(MigrationFileSlot.BACKUP),
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
        assertFalse(files.exists(MigrationFileSlot.PENDING))
    }

    @Test
    fun `reset after post swap validation failure restores source for retry`() {
        val keyId = prepareValidatedPending()
        coordinator.activate(keyId)
        val sourceDigest = checkNotNull(journal.value?.sourceDigest)

        val reset = coordinator.preparePending(keyId)

        assertEquals(MigrationJournalStage.PENDING_CREATED, reset.stage)
        assertEquals(sourceDigest, files.digest(MigrationFileSlot.ACTIVE))
        assertTrue(files.exists(MigrationFileSlot.BACKUP))
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
        assertFalse(files.exists(MigrationFileSlot.PENDING))
    }

    @Test
    fun `cleanup revalidates active before deleting recovery copies`() {
        val keyId = prepareValidatedPending()
        coordinator.activate(keyId)
        coordinator.markPostSwapValidated(keyId)
        files.put(MigrationFileSlot.ACTIVE, "corrupt-after-post-swap-validation")

        val recovered = coordinator.cleanup(keyId)

        assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
        assertEquals(
            files.digest(MigrationFileSlot.BACKUP),
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertTrue(files.exists(MigrationFileSlot.BACKUP))
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
    }

    @Test
    fun `recovery validates rollback and falls back to backup`() {
        val keyId = prepareValidatedPending()
        coordinator.activate(keyId)
        files.put(MigrationFileSlot.ACTIVE, "corrupt-active-database")
        files.put(MigrationFileSlot.ROLLBACK, "corrupt-rollback-database")

        val recovered = coordinator.inspect()

        assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
        assertEquals(
            files.digest(MigrationFileSlot.BACKUP),
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertTrue(files.exists(MigrationFileSlot.BACKUP))
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
    }

    @Test
    fun `recovery uses validated backup when rollback is missing`() {
        val keyId = prepareValidatedPending()
        coordinator.activate(keyId)
        files.put(MigrationFileSlot.ACTIVE, "corrupt-active-database")
        files.delete(MigrationFileSlot.ROLLBACK)

        val recovered = coordinator.inspect()

        assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
        assertEquals(
            files.digest(MigrationFileSlot.BACKUP),
            files.digest(MigrationFileSlot.ACTIVE),
        )
        assertTrue(files.exists(MigrationFileSlot.BACKUP))
    }

    @Test
    fun `activation refuses pending sidecars before moving the active database`() {
        val keyId = prepareValidatedPending()
        files.sidecarSlots += MigrationFileSlot.PENDING

        val error = captureSecurityError {
            coordinator.activate(keyId)
        }

        assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
        assertEquals(MigrationJournalStage.VALIDATED, journal.value?.stage)
        assertTrue(files.exists(MigrationFileSlot.ACTIVE))
        assertTrue(files.exists(MigrationFileSlot.PENDING))
        assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
    }

    @Test
    fun `android file access canonicalizes active and workspace paths`() {
        val root = Files.createTempDirectory("migration-paths").toFile()
        try {
            val active = File(
                root,
                "database/../database/note_secret_search.db",
            )
            val workspace = File(root, "security/../security/migration-v2")

            val files = AndroidMigrationFileSetAccess(active, workspace)

            assertEquals(
                active.canonicalPath,
                files.path(MigrationFileSlot.ACTIVE),
            )
            val workspacePath = workspace.canonicalPath + File.separator
            listOf(
                MigrationFileSlot.BACKUP,
                MigrationFileSlot.PENDING,
                MigrationFileSlot.ROLLBACK,
            ).forEach { slot ->
                assertTrue(
                    files.path(slot).startsWith(workspacePath),
                )
            }
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `android file access rejects active database inside migration workspace`() {
        val root = Files.createTempDirectory("migration-overlap").toFile()
        try {
            val workspace = File(root, "workspace")
            val active = File(
                workspace,
                "backup/note_secret_search.db",
            )

            val error = captureSecurityError {
                AndroidMigrationFileSetAccess(active, workspace)
            }

            assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `android file access rejects active database aliasing a sidecar`() {
        val root = Files.createTempDirectory("migration-sidecar-alias").toFile()
        try {
            val workspace = File(root, "workspace")
            val active = File(
                workspace,
                "backup/note_secret_search.db-wal",
            )

            val error = captureSecurityError {
                AndroidMigrationFileSetAccess(active, workspace)
            }

            assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
        } finally {
            root.deleteRecursively()
        }
    }

    private fun prepareValidatedPending(): String {
        val keyId = "123e4567-e89b-42d3-a456-426614174000"
        coordinator.detect()
        coordinator.markKeyringReady(keyId)
        coordinator.prepareBackup(keyId)
        coordinator.preparePending(keyId)
        files.put(MigrationFileSlot.PENDING, "schema-v4-database")
        coordinator.markRowsCopied(keyId)
        coordinator.markValidated(keyId)
        return keyId
    }
}

private class FakeMigrationJournalStore : MigrationJournalStore {
    var value: MigrationJournal? = null
    var failOnceOnStage: MigrationJournalStage? = null

    override fun read(): MigrationJournal? = value

    override fun write(value: MigrationJournal) {
        if (failOnceOnStage == value.stage) {
            failOnceOnStage = null
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_FAILED,
            )
        }
        this.value = value
    }

    override fun delete() {
        value = null
    }
}

private class FakeMigrationFileSetAccess : MigrationFileSetAccess {
    private val contents = mutableMapOf<MigrationFileSlot, String>()
    val sidecarSlots = mutableSetOf<MigrationFileSlot>()
    var available = Long.MAX_VALUE
    var failMoveToActive = false

    fun put(slot: MigrationFileSlot, value: String) {
        contents[slot] = value
    }

    override fun path(slot: MigrationFileSlot): String = "/fixed/${slot.name.lowercase()}.db"

    override fun exists(slot: MigrationFileSlot): Boolean = contents.containsKey(slot)

    override fun hasSidecars(slot: MigrationFileSlot): Boolean {
        return sidecarSlots.contains(slot)
    }

    override fun sizeBytes(slot: MigrationFileSlot): Long {
        return contents[slot]?.toByteArray()?.size?.toLong() ?: 0L
    }

    override fun availableBytes(): Long = available

    override fun digest(slot: MigrationFileSlot): String? {
        val value = contents[slot] ?: return null
        return MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    override fun copy(from: MigrationFileSlot, to: MigrationFileSlot) {
        contents[to] = checkNotNull(contents[from])
    }

    override fun move(from: MigrationFileSlot, to: MigrationFileSlot) {
        if (to == MigrationFileSlot.ACTIVE && failMoveToActive) {
            throw NativeSecurityException(NativeSecurityErrorCode.MIGRATION_FAILED)
        }
        contents[to] = checkNotNull(contents.remove(from))
    }

    override fun delete(slot: MigrationFileSlot) {
        contents.remove(slot)
    }

    override fun sync(slot: MigrationFileSlot) = Unit
}

private fun captureSecurityError(block: () -> Unit): NativeSecurityException {
    return try {
        block()
        throw AssertionError("Expected NativeSecurityException")
    } catch (error: NativeSecurityException) {
        error
    }
}
