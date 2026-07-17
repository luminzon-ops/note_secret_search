package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal class SecurityKeyringManagerTest : SecurityKeyringTestFixture() {
    @Test
    fun `fresh provisioning persists one envelope and returns derived session keys`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        val masterKey = ByteArray(32) { it.toByte() }
        random.enqueue(masterKey)
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
        val persistedJson = store.bytes!!.toString(StandardCharsets.UTF_8)
        assertFalse(persistedJson.contains("masterKey"))
        assertFalse(persistedJson.contains("databaseKey"))
        assertFalse(persistedJson.contains("fieldKey"))
        listOf(masterKey, result.value!!.databaseKey, result.value!!.fieldKey)
            .map(Base64.getEncoder()::encodeToString)
            .forEach { encodedKey ->
                assertFalse(persistedJson.contains(encodedKey))
            }
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
    fun `security state reports a configured PIN envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        val keyset = SecurityKeysetCodec.decode(store.bytes!!)
        store.write(
            SecurityKeysetCodec.encode(
                keyset.copy(
                    pinEnvelope = PinEnvelope(
                        kdf = PinKdfParameters(
                            memoryKiB = 65_536,
                            iterations = 3,
                            parallelism = 1,
                            salt = ByteArray(16) { (it + 3).toByte() },
                        ),
                        nonce = ByteArray(12) { (it + 20).toByte() },
                        ciphertext = ByteArray(32) { (it + 40).toByte() },
                        tag = ByteArray(16) { (it + 80).toByte() },
                    ),
                ),
            ),
        )

        val state = manager.getSecurityState()

        assertTrue(state.pinConfigured)
    }

    @Test
    fun `configuring a PIN authenticates the system envelope and persists a PIN envelope`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        authenticator.requests.clear()
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        val pin = "2468".toByteArray()
        val result = RecordingNativeResult<Unit>()

        manager.configurePin("Configure fallback PIN", pin, result)

        assertNull(result.error)
        assertEquals(Unit, result.value)
        assertTrue(manager.getSecurityState().pinConfigured)
        assertTrue(pin.all { it == 0.toByte() })
        assertNotNull(SecurityKeysetCodec.decode(store.bytes!!).pinEnvelope)
        assertEquals(2, store.writes)
        assertEquals(
            listOf(SystemAuthenticatorMode.COMBINED),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `PIN is cleared when keyset storage fails before configuration`() {
        store.failReads = true
        val pin = "2468".toByteArray()
        val result = RecordingNativeResult<Unit>()

        manager(apiLevel = 30).configurePin(
            "Configure fallback PIN",
            pin,
            result,
        )

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            result.error?.code,
        )
        assertTrue(pin.all { it == 0.toByte() })
    }

    @Test
    fun `PIN unlock returns the same session keys without system authentication`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        val provision = RecordingNativeResult<NativeUnlockMaterial>()
        manager.provisionWithSystemAuth("Create keyring", provision)
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        authenticator.requests.clear()
        val pin = "2468".toByteArray()
        val unlock = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithPin(pin, unlock)

        assertNull(unlock.error)
        assertArrayEquals(provision.value!!.databaseKey, unlock.value!!.databaseKey)
        assertArrayEquals(provision.value!!.fieldKey, unlock.value!!.fieldKey)
        assertEquals("pin", unlock.value!!.unlockMethod)
        assertTrue(pin.all { it == 0.toByte() })
        assertTrue(authenticator.requests.isEmpty())
    }

    @Test
    fun `sixth PIN attempt is blocked after five consecutive failures`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )

        repeat(5) {
            val pin = "0000".toByteArray()
            val failure = RecordingNativeResult<NativeUnlockMaterial>()

            manager.unlockWithPin(pin, failure)

            assertEquals(
                NativeSecurityErrorCode.PIN_INCORRECT,
                failure.error?.code,
            )
            assertTrue(pin.all { it == 0.toByte() })
        }
        val blockedPin = "2468".toByteArray()
        val blocked = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithPin(blockedPin, blocked)

        assertEquals("PIN_COOLDOWN", blocked.error?.code?.name)
        assertNull(blocked.value)
        assertTrue(blockedPin.all { it == 0.toByte() })
    }

    @Test
    fun `successful PIN unlock after cooldown clears persisted failures`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val firstProcess = manager(apiLevel = 30)
        firstProcess.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        firstProcess.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        repeat(5) {
            firstProcess.unlockWithPin(
                "0000".toByteArray(),
                RecordingNativeResult(),
            )
        }
        val restartedProcess = manager(apiLevel = 30)
        val blocked = RecordingNativeResult<NativeUnlockMaterial>()
        restartedProcess.unlockWithPin("2468".toByteArray(), blocked)
        assertEquals(
            NativeSecurityErrorCode.PIN_COOLDOWN,
            blocked.error?.code,
        )
        pinThrottleClock.elapsedRealtimeMs += 60_000
        pinThrottleClock.wallClockMs += 60_000

        val unlock = RecordingNativeResult<NativeUnlockMaterial>()
        restartedProcess.unlockWithPin("2468".toByteArray(), unlock)

        assertNull(unlock.error)
        assertNotNull(unlock.value)
        assertNull(pinThrottleStore.state)

        val nextFailure = RecordingNativeResult<NativeUnlockMaterial>()
        manager(apiLevel = 30).unlockWithPin(
            "0000".toByteArray(),
            nextFailure,
        )
        assertEquals(
            NativeSecurityErrorCode.PIN_INCORRECT,
            nextFailure.error?.code,
        )
    }

    @Test
    fun `replacing a PIN preserves system envelopes and invalidates the old PIN`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        val provisioned = SecurityKeysetCodec.decode(store.bytes!!)
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 60).toByte() })
        random.enqueue(ByteArray(12) { (it + 100).toByte() })
        val replacement = RecordingNativeResult<Unit>()

        manager.configurePin(
            "Replace fallback PIN",
            "1357".toByteArray(),
            replacement,
        )

        assertNull(replacement.error)
        val replaced = SecurityKeysetCodec.decode(store.bytes!!)
        assertEquals(provisioned.keyId, replaced.keyId)
        assertEquals(provisioned.envelopes, replaced.envelopes)

        val oldPin = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithPin("2468".toByteArray(), oldPin)
        assertEquals(
            NativeSecurityErrorCode.PIN_INCORRECT,
            oldPin.error?.code,
        )

        val newPin = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithPin("1357".toByteArray(), newPin)
        assertNull(newPin.error)
        assertNotNull(newPin.value)
    }

    @Test
    fun `PIN replacement storage failure preserves the previous PIN`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        val previousKeyset = store.bytes!!.clone()
        random.enqueue(ByteArray(16) { (it + 60).toByte() })
        random.enqueue(ByteArray(12) { (it + 100).toByte() })
        store.failOnWrite = store.writes + 1
        val replacement = RecordingNativeResult<Unit>()

        manager.configurePin(
            "Replace fallback PIN",
            "1357".toByteArray(),
            replacement,
        )

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            replacement.error?.code,
        )
        assertArrayEquals(previousKeyset, store.bytes)
        store.failOnWrite = null

        val oldPin = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithPin("2468".toByteArray(), oldPin)
        assertNull(oldPin.error)
        assertNotNull(oldPin.value)

        val rejectedReplacement = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithPin("1357".toByteArray(), rejectedReplacement)
        assertEquals(
            NativeSecurityErrorCode.PIN_INCORRECT,
            rejectedReplacement.error?.code,
        )
    }

    @Test
    fun `replacing a PIN does not inherit the previous PIN cooldown`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        repeat(5) {
            manager.unlockWithPin(
                "0000".toByteArray(),
                RecordingNativeResult(),
            )
        }
        random.enqueue(ByteArray(16) { (it + 60).toByte() })
        random.enqueue(ByteArray(12) { (it + 100).toByte() })
        val replacement = RecordingNativeResult<Unit>()
        manager.configurePin(
            "Replace fallback PIN",
            "1357".toByteArray(),
            replacement,
        )
        assertNull(replacement.error)

        val unlock = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithPin("1357".toByteArray(), unlock)

        assertNull(unlock.error)
        assertNotNull(unlock.value)
    }

    @Test
    fun `removing a PIN authenticates the system envelope and preserves system keys`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        val aliasesBefore = SecurityKeysetCodec.decode(store.bytes!!)
            .envelopes
            .map { it.keyAlias }
        authenticator.requests.clear()
        val result = RecordingNativeResult<Unit>()

        manager.removePin("Remove fallback PIN", result)

        assertNull(result.error)
        assertEquals(Unit, result.value)
        assertFalse(manager.getSecurityState().pinConfigured)
        assertEquals(
            aliasesBefore,
            SecurityKeysetCodec.decode(store.bytes!!).envelopes.map {
                it.keyAlias
            },
        )
        assertEquals(3, store.writes)
        assertEquals(
            listOf(SystemAuthenticatorMode.COMBINED),
            authenticator.requests.map { it.mode },
        )
    }

    @Test
    fun `removing an absent PIN authenticates without rewriting the keyset`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val manager = manager(apiLevel = 30)
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        random.enqueue(ByteArray(16) { (it + 40).toByte() })
        random.enqueue(ByteArray(12) { (it + 80).toByte() })
        manager.configurePin(
            "Configure fallback PIN",
            "2468".toByteArray(),
            RecordingNativeResult(),
        )
        manager.removePin(
            "Remove fallback PIN",
            RecordingNativeResult(),
        )
        val writesAfterRemoval = store.writes
        authenticator.requests.clear()
        val repeated = RecordingNativeResult<Unit>()

        manager.removePin("Remove fallback PIN again", repeated)

        assertNull(repeated.error)
        assertEquals(Unit, repeated.value)
        assertEquals(writesAfterRemoval, store.writes)
        assertEquals(
            listOf(SystemAuthenticatorMode.COMBINED),
            authenticator.requests.map { it.mode },
        )
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
    fun `api 29 biometric cancellation falls back to authenticated device credential`() {
        provisionApi29WithBiometric()
        authenticator.requests.clear()
        authenticator.enqueue(
            AuthOutcome.Error(NativeSecurityErrorCode.AUTH_CANCELLED),
        )
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
            pinThrottle = testPinAttemptThrottle(),
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertEquals(
            NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
            result.error?.code,
        )
        assertEquals(0, keys.createCalls)
    }
}
