package com.example.note_secret_search.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import org.json.JSONObject
import java.security.MessageDigest

internal class SecurityKeyringMigrationTest : SecurityKeyringTestFixture() {
    @Test
    fun `blank legacy password blocks migration before keyset creation`() {
        legacy.legacyPasswordPresent = true
        legacy.legacyPassword = ""
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.beginLegacyMigration("Upgrade security", result)

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            result.error?.code,
        )
        assertNull(store.bytes)
        assertEquals(0, store.writes)
    }

    @Test
    fun `corrupt legacy preference state requires recovery`() {
        legacy.stateFailure = ClassCastException("wrong preference type")
        val manager = manager(apiLevel = 30)

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertNull(store.bytes)
    }

    @Test
    fun `keyset read failure requires recovery`() {
        store.failReads = true
        val manager = manager(apiLevel = 30)

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
    }

    @Test
    fun `corrupt legacy preference state blocks keyset provisioning`() {
        legacy.stateFailure = ClassCastException("wrong preference type")
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            result.error?.code,
        )
        assertNull(store.bytes)
        assertEquals(0, store.writes)
    }

    @Test
    fun `existing database without credentials requires recovery`() {
        val fileCoordinator = MigrationFileCoordinator(
            files = FinalizationMigrationFileSetAccess(),
            journalStore = FinalizationMigrationJournalStore(),
        )
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = fileCoordinator,
        )

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertNull(store.bytes)
    }

    @Test
    fun `existing database without credentials cannot provision replacement keyset`() {
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = FinalizationMigrationJournalStore(),
            ),
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(
            NativeSecurityErrorCode.RECOVERY_REQUIRED,
            result.error?.code,
        )
        assertNull(store.bytes)
        assertEquals(0, store.writes)
    }

    @Test
    fun `legacy marker does not mask a corrupt migration keyset`() {
        legacy.legacyPasswordPresent = true
        store.bytes = """{"version":3,"keyId":"broken"}""".toByteArray()
        val manager = manager(apiLevel = 30)

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
    }

    @Test
    fun `legacy marker does not mask loss of every key recovery path`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        keys.keys.clear()
        legacy.legacyPasswordPresent = true

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
    }

    @Test
    fun `keyring ready journal without its keyset requires recovery`() {
        val migrationJournal = FinalizationMigrationJournalStore().apply {
            value = MigrationJournal(
                stage = MigrationJournalStage.KEYRING_READY,
                keyId = TEST_KEY_ID,
            )
        }
        legacy.legacyPasswordPresent = true
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = migrationJournal,
            ),
        )

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertNull(store.bytes)
    }

    @Test
    fun `legacy password loss before cleanup complete requires recovery`() {
        val migrationJournal = FinalizationMigrationJournalStore()
        val migrationFiles = FinalizationMigrationFileSetAccess()
        val fileCoordinator = MigrationFileCoordinator(
            files = migrationFiles,
            journalStore = migrationJournal,
        )
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create migration keyring",
            RecordingNativeResult(),
        )
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = fileCoordinator,
        )
        val keyId = SecurityKeysetCodec.decode(store.bytes!!).keyId
        migrationJournal.value = MigrationJournal(
            stage = MigrationJournalStage.BACKUP_READY,
            keyId = keyId,
            sourceDigest = "a".repeat(64),
        )
        legacy.legacyPasswordPresent = false

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
    }

    @Test
    fun `migration uses system recovery when the pin envelope is corrupt`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        var expectedKeyId: String? = null
        val manager = manager(
            apiLevel = 30,
            migrationCompletionVerifier = MigrationCompletionVerifier { keyId, digest ->
                keyId == expectedKeyId && digest == "active-digest"
            },
        )
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        manager.configurePin(
            "Configure PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        val root = JSONObject(store.bytes!!.toString(Charsets.UTF_8))
        root.getJSONObject("pinEnvelope").put("nonce", "broken")
        store.bytes = root.toString().toByteArray()
        legacy.legacyPasswordPresent = true
        val begin = RecordingNativeResult<NativeUnlockMaterial>()

        manager.beginLegacyMigration("Upgrade security", begin)

        assertNull(begin.error)
        expectedKeyId = begin.value!!.keyId
        val commit = RecordingNativeResult<Unit>()
        manager.commitLegacyMigration(
            begin.value!!.keyId,
            "active-digest",
            commit,
        )

        assertNull(commit.error)
        assertFalse(legacy.legacyPasswordPresent)
        val state = manager.getSecurityState()
        assertEquals(SecurityStatus.LOCKED, state.status)
        assertTrue(state.pinResetRequired)
        assertFalse(state.pinConfigured)
    }

    @Test
    fun `cleanup complete migration configures pin before clearing legacy password`() {
        val migrationJournal = FinalizationMigrationJournalStore()
        val migrationFiles = FinalizationMigrationFileSetAccess()
        val fileCoordinator = MigrationFileCoordinator(
            files = migrationFiles,
            journalStore = migrationJournal,
        )
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create migration keyring",
            RecordingNativeResult(),
        )
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = fileCoordinator,
        )
        val keyId = SecurityKeysetCodec.decode(store.bytes!!).keyId
        val activeDigest = migrationFiles.digest(MigrationFileSlot.ACTIVE)!!
        migrationJournal.value = MigrationJournal(
            stage = MigrationJournalStage.CLEANUP_COMPLETE,
            keyId = keyId,
            sourceDigest = "a".repeat(64),
            pendingDigest = activeDigest,
            activeDigest = activeDigest,
        )
        legacy.legacyPasswordPresent = true
        val result = RecordingNativeResult<Unit>()

        manager.configurePin(
            "Migrate legacy PIN",
            "2468".toByteArray(),
            result,
        )

        assertNull(result.error)
        assertEquals(Unit, result.value)
        assertTrue(legacy.legacyPasswordPresent)
        assertNotNull(
            SecurityKeysetCodec.decode(store.bytes!!).pinEnvelope,
        )
    }

    @Test
    fun `migration journal cannot finish before legacy password commit`() {
        val migrationJournal = FinalizationMigrationJournalStore().apply {
            value = MigrationJournal(
                stage = MigrationJournalStage.CLEANUP_COMPLETE,
                keyId = TEST_KEY_ID,
                sourceDigest = "a".repeat(64),
                pendingDigest = "b".repeat(64),
                activeDigest = "b".repeat(64),
            )
        }
        legacy.legacyPasswordPresent = true
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = migrationJournal,
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            manager.finishLegacyMigration(TEST_KEY_ID)
        }

        assertEquals(NativeSecurityErrorCode.MIGRATION_REQUIRED, error.code)
        assertNotNull(migrationJournal.value)
    }

    @Test
    fun `migration journal cannot finish when keyset is missing`() {
        val migrationJournal = cleanupCompleteJournal(TEST_KEY_ID)
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = migrationJournal,
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            manager.finishLegacyMigration(TEST_KEY_ID)
        }

        assertEquals(NativeSecurityErrorCode.RECOVERY_REQUIRED, error.code)
        assertNotNull(migrationJournal.value)
    }

    @Test
    fun `migration journal cannot finish when keyset is corrupt`() {
        store.bytes = """{"version":3,"keyId":"broken"}""".toByteArray()
        val migrationJournal = cleanupCompleteJournal(TEST_KEY_ID)
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = migrationJournal,
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            manager.finishLegacyMigration(TEST_KEY_ID)
        }

        assertEquals(NativeSecurityErrorCode.RECOVERY_REQUIRED, error.code)
        assertNotNull(migrationJournal.value)
    }

    @Test
    fun `migration journal cannot finish when keyset id differs`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create unrelated keyring",
            RecordingNativeResult(),
        )
        val migrationJournal = cleanupCompleteJournal(TEST_KEY_ID)
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = MigrationFileCoordinator(
                files = FinalizationMigrationFileSetAccess(),
                journalStore = migrationJournal,
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            manager.finishLegacyMigration(TEST_KEY_ID)
        }

        assertEquals(NativeSecurityErrorCode.RECOVERY_REQUIRED, error.code)
        assertNotNull(migrationJournal.value)
    }

    @Test
    fun `begin provisions once and resumes the same migration keyring`() {
        legacy.legacyPasswordPresent = true
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        val first = RecordingNativeResult<NativeUnlockMaterial>()

        manager.beginLegacyMigration("Upgrade security", first)

        assertNull(first.error)
        assertNotNull(first.value)
        assertEquals(SecurityStatus.LEGACY_MIGRATION_REQUIRED, manager.getSecurityState().status)
        assertTrue(legacy.legacyPasswordPresent)
        val resumed = RecordingNativeResult<NativeUnlockMaterial>()

        manager.beginLegacyMigration("Resume security upgrade", resumed)

        assertNull(resumed.error)
        assertEquals(first.value!!.keyId, resumed.value!!.keyId)
        assertArrayEquals(first.value!!.databaseKey, resumed.value!!.databaseKey)
        assertArrayEquals(first.value!!.fieldKey, resumed.value!!.fieldKey)
        assertEquals(1, store.writes)
    }

    @Test
    fun `commit before post swap validation preserves legacy marker`() {
        legacy.legacyPasswordPresent = true
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        val begin = RecordingNativeResult<NativeUnlockMaterial>()
        manager.beginLegacyMigration(
            "Upgrade security",
            begin,
        )
        val result = RecordingNativeResult<Unit>()

        manager.commitLegacyMigration(
            begin.value!!.keyId,
            "active-digest",
            result,
        )

        assertEquals(
            NativeSecurityErrorCode.RECOVERY_REQUIRED,
            result.error?.code,
        )
        assertTrue(legacy.legacyPasswordPresent)
        assertEquals(
            SecurityStatus.LEGACY_MIGRATION_REQUIRED,
            manager.getSecurityState().status,
        )
    }

    @Test
    fun `commit before file cleanup preserves legacy marker`() {
        val migrationJournal = FinalizationMigrationJournalStore()
        val migrationFiles = FinalizationMigrationFileSetAccess()
        val fileCoordinator = MigrationFileCoordinator(
            files = migrationFiles,
            journalStore = migrationJournal,
        )
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create migration keyring",
            RecordingNativeResult(),
        )
        val manager = manager(
            apiLevel = 30,
            migrationFileCoordinator = fileCoordinator,
            migrationCompletionVerifier = fileCoordinator,
        )
        val keyId = SecurityKeysetCodec.decode(store.bytes!!).keyId
        val activeDigest = migrationFiles.digest(MigrationFileSlot.ACTIVE)!!
        migrationJournal.value = MigrationJournal(
            stage = MigrationJournalStage.POST_SWAP_VALIDATED,
            keyId = keyId,
            sourceDigest = "a".repeat(64),
            pendingDigest = activeDigest,
            activeDigest = activeDigest,
        )
        legacy.legacyPasswordPresent = true
        val result = RecordingNativeResult<Unit>()

        manager.commitLegacyMigration(keyId, activeDigest, result)

        assertEquals(
            NativeSecurityErrorCode.RECOVERY_REQUIRED,
            result.error?.code,
        )
        assertTrue(legacy.legacyPasswordPresent)
        assertNotNull(migrationJournal.value)
    }

    @Test
    fun `commit clears legacy marker after matching post swap validation`() {
        legacy.legacyPasswordPresent = true
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        var expectedKeyId: String? = null
        val verifier = MigrationCompletionVerifier { keyId, digest ->
            keyId == expectedKeyId && digest == "active-digest"
        }
        val manager = manager(
            apiLevel = 30,
            migrationCompletionVerifier = verifier,
        )
        val begin = RecordingNativeResult<NativeUnlockMaterial>()
        manager.beginLegacyMigration("Upgrade security", begin)
        expectedKeyId = begin.value!!.keyId
        val result = RecordingNativeResult<Unit>()

        manager.commitLegacyMigration(
            begin.value!!.keyId,
            "active-digest",
            result,
        )

        assertNull(result.error)
        assertFalse(legacy.legacyPasswordPresent)
        assertEquals(SecurityStatus.LOCKED, manager.getSecurityState().status)
    }

    @Test
    fun `abort preserves legacy and migration keyring for retry`() {
        legacy.legacyPasswordPresent = true
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.beginLegacyMigration(
            "Upgrade security",
            RecordingNativeResult(),
        )
        val encoded = store.bytes!!.clone()
        val result = RecordingNativeResult<Unit>()

        manager.abortLegacyMigration(result)

        assertNull(result.error)
        assertTrue(legacy.legacyPasswordPresent)
        assertArrayEquals(encoded, store.bytes)
        assertEquals(SecurityStatus.LEGACY_MIGRATION_REQUIRED, manager.getSecurityState().status)
    }

    private fun cleanupCompleteJournal(
        keyId: String,
    ): FinalizationMigrationJournalStore {
        return FinalizationMigrationJournalStore().apply {
            value = MigrationJournal(
                stage = MigrationJournalStage.CLEANUP_COMPLETE,
                keyId = keyId,
                sourceDigest = "a".repeat(64),
                pendingDigest = "b".repeat(64),
                activeDigest = "b".repeat(64),
            )
        }
    }

    private companion object {
        const val TEST_KEY_ID =
            "123e4567-e89b-42d3-a456-426614174000"
    }
}

private class FinalizationMigrationJournalStore : MigrationJournalStore {
    var value: MigrationJournal? = null

    override fun read(): MigrationJournal? = value

    override fun write(value: MigrationJournal) {
        this.value = value
    }

    override fun delete() {
        value = null
    }
}

private class FinalizationMigrationFileSetAccess : MigrationFileSetAccess {
    private val active = "validated-schema-v4".toByteArray()

    override fun path(slot: MigrationFileSlot): String =
        "/fixed/${slot.name.lowercase()}.db"

    override fun exists(slot: MigrationFileSlot): Boolean =
        slot == MigrationFileSlot.ACTIVE

    override fun hasSidecars(slot: MigrationFileSlot): Boolean = false

    override fun sizeBytes(slot: MigrationFileSlot): Long =
        if (exists(slot)) active.size.toLong() else 0L

    override fun availableBytes(): Long = Long.MAX_VALUE

    override fun digest(slot: MigrationFileSlot): String? {
        if (!exists(slot)) {
            return null
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(active)
            .joinToString("") { "%02x".format(it) }
    }

    override fun copy(from: MigrationFileSlot, to: MigrationFileSlot) =
        error("not used")

    override fun move(from: MigrationFileSlot, to: MigrationFileSlot) =
        error("not used")

    override fun delete(slot: MigrationFileSlot) = Unit

    override fun sync(slot: MigrationFileSlot) = Unit
}
