package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

internal class SecurityKeyringRecoveryTest : SecurityKeyringTestFixture() {
    @Test
    fun `legacy password reports migration required and provisioning does not overwrite it`() {
        legacy.legacyPasswordPresent = true
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        val state = manager.getSecurityState()
        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(SecurityStatus.LEGACY_MIGRATION_REQUIRED, state.status)
        assertEquals(NativeSecurityErrorCode.MIGRATION_REQUIRED, result.error?.code)
        assertEquals(0, store.writes)
        assertEquals(0, keys.createCalls)
    }

    @Test
    fun `corrupt envelope reports recovery and fails unlock with stable corruption code`() {
        store.bytes = """{"version":2,"keyId":"broken"}""".toByteArray()
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        val state = manager.getSecurityState()
        manager.unlockWithSystemAuth("Unlock", result)

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertEquals(NativeSecurityErrorCode.ENVELOPE_CORRUPT, result.error?.code)
    }

    @Test
    fun `missing wrapping alias reports recovery instead of generating a new master key`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult<NativeUnlockMaterial>(),
        )
        keys.keys.clear()
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        val state = manager.getSecurityState()
        manager.unlockWithSystemAuth("Unlock", unlock)

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertEquals(NativeSecurityErrorCode.RECOVERY_REQUIRED, unlock.error?.code)
        assertEquals(1, keys.createCalls)
    }

    @Test
    fun `authentication cancellation leaves an unprovisioned keyring and removes generated alias`() {
        authenticator.enqueue(AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED))
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertEquals(SecurityStatus.UNPROVISIONED, manager.getSecurityState().status)
        assertEquals(1, keys.deleteCalls)
        assertNull(store.bytes)
    }

    @Test
    fun `key invalidation fails unlock without replacing stored envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult<NativeUnlockMaterial>(),
        )
        keys.invalidated = true
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithSystemAuth("Unlock", unlock)

        assertEquals(NativeSecurityErrorCode.KEY_INVALIDATED, unlock.error?.code)
        assertEquals(1, keys.createCalls)
        assertNotNull(store.bytes)
    }

    @Test
    fun `tampered authentication tag fails unlock as corrupt envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult<NativeUnlockMaterial>(),
        )
        val keyset = SecurityKeysetCodec.decode(store.bytes!!)
        val envelope = keyset.envelopes.single()
        val tamperedTag = envelope.tag.clone().also {
            it[0] = (it[0].toInt() xor 1).toByte()
        }
        store.bytes = SecurityKeysetCodec.encode(
            keyset.copy(envelopes = listOf(envelope.copy(tag = tamperedTag))),
        )
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithSystemAuth("Unlock", unlock)

        assertEquals(NativeSecurityErrorCode.ENVELOPE_CORRUPT, unlock.error?.code)
        assertNull(unlock.value)
    }

    @Test
    fun `state rejects stored security level that disagrees with the keystore`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 31)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult<NativeUnlockMaterial>(),
        )
        val keyset = SecurityKeysetCodec.decode(store.bytes!!)
        val envelope = keyset.envelopes.single()
        store.bytes = SecurityKeysetCodec.encode(
            keyset.copy(
                envelopes = listOf(
                    envelope.copy(securityLevel = KeySecurityLevel.STRONG_BOX),
                ),
            ),
        )

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.RECOVERY_REQUIRED, state.status)
        assertEquals(KeySecurityLevel.UNKNOWN, state.securityLevel)
    }

    @Test
    fun `api 30 keeps StrongBox keysets usable when legacy KeyInfo reports tee`() {
        val ambiguousKeys = FakeWrappingKeyRepository(
            generatedLevel = KeySecurityLevel.STRONG_BOX,
            loadedLevel = KeySecurityLevel.TEE,
        )
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = ambiguousKeys,
            authenticator = authenticator,
            capabilities = { capabilities },
            random = random,
        )
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult<NativeUnlockMaterial>(),
        )

        val state = manager.getSecurityState()

        assertEquals(SecurityStatus.LOCKED, state.status)
        assertEquals(KeySecurityLevel.UNKNOWN, state.securityLevel)
    }

    @Test
    fun `atomic persistence failure returns storage error and removes generated alias`() {
        store.failWrites = true
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            result.error?.code,
        )
        assertEquals(1, keys.deleteCalls)
        assertNull(result.value)
    }

    @Test
    fun `security state map uses the channel contract`() {
        val state = manager(apiLevel = 30).getSecurityState().toChannelMap()

        assertEquals("unprovisioned", state["status"])
        assertEquals(false, state["pinConfigured"])
        assertEquals(true, state["deviceCredentialAvailable"])
        assertEquals(true, state["strongBiometricAvailable"])
        assertEquals("unknown", state["securityLevel"])
        assertFalse(state.containsKey("keyId"))
    }
}
