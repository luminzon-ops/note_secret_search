package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal class SecurityKeyringManagerApi29Test : SecurityKeyringTestFixture() {
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
        assertEquals(1, store.writes)
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
    fun `api 29 biometric cancellation returns to the locked state`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        authenticator.enqueue(
            AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED),
        )
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).unlockWithSystemAuth("Unlock", unlock)

        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, unlock.error?.code)
        assertNull(unlock.value)
        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
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
        authenticator.enqueue(
            AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED),
        )
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
    fun `api 29 final keyset storage failure falls back to the device envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        store.failOnWrite = 1
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 29).provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        val persisted = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL),
            persisted.envelopes.map { it.kind },
        )
        assertEquals(2, store.writes)
        assertEquals(1, keys.keys.size)
        assertEquals(1, keys.deleteCalls)
    }

    @Test
    fun `required key creation failure removes an alias created before the error`() {
        keys.failAfterCreatePolicy = WrappingKeyPolicy.COMBINED_AUTH_PER_USE
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager(apiLevel = 30).provisionWithSystemAuth("Create keyring", result)

        assertEquals(NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE, result.error?.code)
        assertTrue(keys.keys.isEmpty())
        assertEquals(1, keys.deleteCalls)
        assertNull(store.bytes)
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
}
