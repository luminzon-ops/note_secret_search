package com.example.note_secret_search.security

import android.content.ContextWrapper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidMigrationFileSetInstrumentationTest {
    @Test
    fun copiesMovesAndDeletesCheckpointedMainDatabase() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(
            context.noBackupFilesDir,
            "security/migration-file-test-${UUID.randomUUID()}",
        )
        val active = File(root, "active/note_secret_search.db")
        val workspace = File(root, "workspace")
        val files = AndroidMigrationFileSetAccess(active, workspace)
        try {
            writeMember(active, byteArrayOf(1, 2, 3))
            val activeDigest = files.digest(MigrationFileSlot.ACTIVE)

            files.copy(MigrationFileSlot.ACTIVE, MigrationFileSlot.BACKUP)

            assertEquals(activeDigest, files.digest(MigrationFileSlot.BACKUP))
            assertEquals(
                active.readBytes().toList(),
                File(files.path(MigrationFileSlot.BACKUP)).readBytes().toList(),
            )
            assertFalse(
                File("${files.path(MigrationFileSlot.BACKUP)}-wal").exists(),
            )
            assertFalse(
                File("${files.path(MigrationFileSlot.BACKUP)}-shm").exists(),
            )

            files.move(MigrationFileSlot.BACKUP, MigrationFileSlot.PENDING)

            assertFalse(files.exists(MigrationFileSlot.BACKUP))
            assertTrue(files.exists(MigrationFileSlot.PENDING))
            assertEquals(activeDigest, files.digest(MigrationFileSlot.PENDING))

            files.delete(MigrationFileSlot.PENDING)

            assertFalse(files.exists(MigrationFileSlot.PENDING))
            assertFalse(File("${files.path(MigrationFileSlot.PENDING)}-wal").exists())
            assertFalse(File("${files.path(MigrationFileSlot.PENDING)}-shm").exists())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun refusesSourceWithWalBeforeCreatingBackup() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(
            context.noBackupFilesDir,
            "security/migration-sidecar-test-${UUID.randomUUID()}",
        )
        val active = File(root, "active/note_secret_search.db")
        val workspace = File(root, "workspace")
        val files = AndroidMigrationFileSetAccess(active, workspace)
        try {
            writeMember(active, byteArrayOf(1, 2, 3))
            writeMember(File("${active.path}-wal"), byteArrayOf(4, 5))

            val error = captureSecurityError {
                files.copy(
                    MigrationFileSlot.ACTIVE,
                    MigrationFileSlot.BACKUP,
                )
            }

            assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
            assertFalse(files.exists(MigrationFileSlot.BACKUP))
            assertTrue(active.isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun corruptPendingAtOldMovedRestoresRollbackForRetry() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(
            context.noBackupFilesDir,
            "$MIGRATION_PATH_SENTINEL-${UUID.randomUUID()}",
        )
        val isolatedContext = object : ContextWrapper(context) {
            override fun getNoBackupFilesDir(): File = root
        }
        val active = File(root, "active/note_secret_search.db")
        val workspace = File(root, "workspace")
        val files = AndroidMigrationFileSetAccess(active, workspace)
        val journalStore = AtomicFileMigrationJournalStore(isolatedContext)
        try {
            val source = byteArrayOf(1, 3, 3, 7)
            val pending = byteArrayOf(2, 4, 6, 8)
            writeMember(active, source)
            files.copy(MigrationFileSlot.ACTIVE, MigrationFileSlot.BACKUP)
            val sourceDigest = checkNotNull(
                files.digest(MigrationFileSlot.ACTIVE),
            )
            writeMember(File(files.path(MigrationFileSlot.PENDING)), pending)
            val pendingDigest = checkNotNull(
                files.digest(MigrationFileSlot.PENDING),
            )
            files.move(MigrationFileSlot.ACTIVE, MigrationFileSlot.ROLLBACK)
            writeMember(
                File(files.path(MigrationFileSlot.PENDING)),
                byteArrayOf(9, 9, 9),
            )
            journalStore.write(
                MigrationJournal(
                    stage = MigrationJournalStage.OLD_MOVED,
                    keyId = TEST_KEY_ID,
                    sourceDigest = sourceDigest,
                    pendingDigest = pendingDigest,
                ),
            )

            val recovered = MigrationFileCoordinator(
                files = files,
                journalStore = journalStore,
            ).inspect()

            assertEquals(MigrationJournalStage.BACKUP_READY, recovered.stage)
            assertEquals(source.toList(), active.readBytes().toList())
            assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
            assertFalse(files.exists(MigrationFileSlot.PENDING))
            assertTrue(files.exists(MigrationFileSlot.BACKUP))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun failedPostSwapValidationRestoresLegacyActiveForRetry() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(
            context.noBackupFilesDir,
            "security/migration-post-swap-test-${UUID.randomUUID()}",
        )
        val isolatedContext = object : ContextWrapper(context) {
            override fun getNoBackupFilesDir(): File = root
        }
        val active = File(root, "active/note_secret_search.db")
        val workspace = File(root, "workspace")
        val files = AndroidMigrationFileSetAccess(active, workspace)
        val coordinator = MigrationFileCoordinator(
            files = files,
            journalStore = AtomicFileMigrationJournalStore(isolatedContext),
        )
        try {
            val source = byteArrayOf(1, 3, 3, 7)
            val pending = byteArrayOf(2, 4, 6, 8)
            writeMember(active, source)
            coordinator.detect()
            coordinator.markKeyringReady(TEST_KEY_ID)
            coordinator.prepareBackup(TEST_KEY_ID)
            coordinator.preparePending(TEST_KEY_ID)
            writeMember(File(files.path(MigrationFileSlot.PENDING)), pending)
            coordinator.markRowsCopied(TEST_KEY_ID)
            coordinator.markValidated(TEST_KEY_ID)
            coordinator.activate(TEST_KEY_ID)

            val reset = coordinator.preparePending(TEST_KEY_ID)

            assertEquals(MigrationJournalStage.PENDING_CREATED, reset.stage)
            assertEquals(source.toList(), active.readBytes().toList())
            assertTrue(files.exists(MigrationFileSlot.BACKUP))
            assertFalse(files.exists(MigrationFileSlot.ROLLBACK))
            assertFalse(files.exists(MigrationFileSlot.PENDING))
        } finally {
            root.deleteRecursively()
        }
    }

    private fun writeMember(file: File, bytes: ByteArray) {
        checkNotNull(file.parentFile).mkdirs()
        file.writeBytes(bytes)
    }

    private fun captureSecurityError(
        block: () -> Unit,
    ): NativeSecurityException {
        return try {
            block()
            throw AssertionError("Expected NativeSecurityException")
        } catch (error: NativeSecurityException) {
            error
        }
    }

    private companion object {
        const val TEST_KEY_ID = "123e4567-e89b-42d3-a456-426614174000"
        const val MIGRATION_PATH_SENTINEL =
            "PHASE2_MIGRATION_PATH_SENTINEL_7E31A4"
    }
}
