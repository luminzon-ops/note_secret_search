package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityKeyringManagerTest {
    private val store = FakeSecurityEnvelopeStore()
    private val legacy = FakeLegacySecurityDetector()
    private val keys = FakeWrappingKeyRepository()
    private val authenticator = FakeSystemAuthenticator()
    private val random = FixedRandomSource()
    private val capabilities = SystemAuthCapabilities(
        deviceCredentialAvailable = true,
        strongBiometricAvailable = true,
    )

    @Test
    fun `fresh provisioning persists one envelope and returns derived session keys`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertArrayEquals(
            hex("1ca03149418a383c3e76b0d7ae051f0bb41f6ccd25b92c52c50ba1a7eb2732d3"),
            result.value!!.databaseKey,
        )
        assertArrayEquals(
            hex("6120423c80ff3360487f604d97a73796dce6816a33c9ba88ddde1606f02f5261"),
            result.value!!.fieldKey,
        )
        assertEquals("system", result.value!!.unlockMethod)
        assertEquals(1, store.writes)
        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(EnvelopeKind.COMBINED, persisted.envelopes.single().kind)
        assertFalse(
            store.bytes!!.toString(StandardCharsets.UTF_8)
                .contains(result.value!!.databaseKey.toString()),
        )
    }

    @Test
    fun `existing envelope unlocks the same derived keys without rewriting storage`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        val provision = RecordingNativeResult<NativeUnlockMaterial>()
        manager.provisionWithSystemAuth("Create keyring", provision)
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithSystemAuth("Unlock", unlock)

        assertNull(unlock.error)
        assertArrayEquals(provision.value!!.databaseKey, unlock.value!!.databaseKey)
        assertArrayEquals(provision.value!!.fieldKey, unlock.value!!.fieldKey)
        assertEquals(1, store.writes)
    }

    @Test
    fun `api 29 provisions device then optional biometric envelopes`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 29)

        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )

        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL, EnvelopeKind.BIOMETRIC),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(
            listOf(
                SystemAuthenticatorMode.DEVICE_CREDENTIAL,
                SystemAuthenticatorMode.BIOMETRIC,
            ),
            authenticator.requests.map { it.mode },
        )
        assertNull(authenticator.requests.first().cipher)
        assertNotNull(authenticator.requests.last().cipher)
        assertEquals(2, store.writes)
    }

    @Test
    fun `api 29 without strong biometric provisions only device credential envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(
            apiLevel = 29,
            authCapabilities = capabilities.copy(strongBiometricAvailable = false),
        )

        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )

        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(
            listOf(SystemAuthenticatorMode.DEVICE_CREDENTIAL),
            authenticator.requests.map { it.mode },
        )
        assertEquals(1, store.writes)
    }

    @Test
    fun `api 29 unlock prefers biometric envelope when available`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).unlockWithSystemAuth("Unlock", unlock)

        assertNull(unlock.error)
        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `api 30 unlocks a keyset provisioned before the os upgrade`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        val upgradedManager = manager(apiLevel = 30)
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        val state = upgradedManager.getSecurityState()
        upgradedManager.unlockWithSystemAuth("Unlock after upgrade", unlock)

        assertEquals(SecurityStatus.LOCKED, state.status)
        assertNull(unlock.error)
        assertNotNull(unlock.value)
        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `api 29 biometric cancellation falls back to authenticated device credential`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        authenticator.enqueue(AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED))
        authenticator.enqueue(AuthOutcome.Success)
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).unlockWithSystemAuth("Unlock", unlock)

        assertNull(unlock.error)
        assertNotNull(unlock.value)
        assertEquals(
            listOf(
                SystemAuthenticatorMode.BIOMETRIC,
                SystemAuthenticatorMode.DEVICE_CREDENTIAL,
            ),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `api 29 missing optional biometric alias falls back to device credential`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        val biometricAlias = keys.keys.keys.single {
            it.endsWith(".${EnvelopeKind.BIOMETRIC.serializedName}")
        }
        keys.keys.remove(biometricAlias)
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).unlockWithSystemAuth("Unlock", unlock)

        assertNull(unlock.error)
        assertNotNull(unlock.value)
        assertEquals(
            listOf(SystemAuthenticatorMode.DEVICE_CREDENTIAL),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `api 29 biometric cancellation during provisioning keeps device envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        authenticator.enqueue(AuthOutcome.Success)
        authenticator.enqueue(AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED))
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(1, store.writes)
        assertEquals(1, keys.deleteCalls)
    }

    @Test
    fun `api 29 optional biometric storage failure preserves a usable device keyset`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        store.failOnWrite = 2
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(1, keys.keys.size)
        assertEquals(1, keys.deleteCalls)
    }

    @Test
    fun `api 29 optional biometric keystore failure preserves device provisioning`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        keys.failPolicy = WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(1, keys.keys.size)
    }

    @Test
    fun `api 29 biometric auth failure does not fall back to device credential`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        authenticator.enqueue(AuthOutcome.Error(NativeSecurityErrorCode.AUTH_FAILED))
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).unlockWithSystemAuth("Unlock", unlock)

        assertEquals(NativeSecurityErrorCode.AUTH_FAILED, unlock.error?.code)
        assertNull(unlock.value)
        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `provisioning requires a configured device credential`() {
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = {
                capabilities.copy(deviceCredentialAvailable = false)
            },
            random = random,
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(
            NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
            result.error?.code,
        )
        assertEquals(0, keys.createCalls)
    }

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
        val tamperedTag = envelope.tag.clone().also { it[0] = (it[0].toInt() xor 1).toByte() }
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

    @Test
    fun `lock completes without returning key material`() {
        assertNull(manager(apiLevel = 30).lock())
    }

    @Test
    fun `lock cancels an in flight authentication before keys can be delivered`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val deferredAuthenticator = DeferredSystemAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = deferredAuthenticator,
            capabilities = { capabilities },
            random = random,
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)
        manager.lock()
        deferredAuthenticator.succeed()

        assertEquals(1, deferredAuthenticator.cancelCalls)
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertNull(result.value)
        assertNull(store.bytes)
    }

    @Test
    fun `late biometric cancellation after lock does not start credential fallback`() {
        provisionApi29WithBiometric()
        val deferredAuthenticator = DeferredSystemAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 29,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = deferredAuthenticator,
            capabilities = { capabilities },
            random = random,
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithSystemAuth("Unlock", result)
        manager.lock()
        deferredAuthenticator.fail(NativeSecurityErrorCode.AUTH_CANCELLED)

        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
            deferredAuthenticator.requests.map { it.mode },
        )
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertNull(result.value)
    }

    private fun provisionApi29WithBiometric() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 29).provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
    }

    private fun manager(
        apiLevel: Int,
        authCapabilities: SystemAuthCapabilities = capabilities,
    ): NativeKeyringManager {
        return NativeKeyringManager(
            apiLevel = apiLevel,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { authCapabilities },
            random = random,
        )
    }

    private fun hex(value: String): ByteArray {
        return value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
}

private class DeferredSystemAuthenticator : SystemAuthenticator {
    val requests = mutableListOf<SystemAuthRequest>()
    var cancelCalls = 0
    private val terminals = mutableListOf<AuthenticationTerminal>()

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        requests += request
        terminals += terminal
    }

    override fun cancel() {
        cancelCalls += 1
    }

    fun succeed() {
        terminals.last().succeeded(requests.last().cipher)
    }

    fun fail(code: NativeSecurityErrorCode) {
        terminals.last().failed(NativeSecurityException(code))
    }
}
