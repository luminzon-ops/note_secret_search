package com.example.note_secret_search.security

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.Key
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeSecurityLifecycleInstrumentationTest {
    private lateinit var context: Context
    private lateinit var sandboxRoot: File
    private lateinit var isolatedContext: Context
    private lateinit var wrappingKeys: InstrumentationWrappingKeys

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        sandboxRoot = File(
            context.noBackupFilesDir,
            "instrumentation/native-security-${UUID.randomUUID()}",
        )
        isolatedContext = object : ContextWrapper(context) {
            override fun getNoBackupFilesDir(): File = sandboxRoot
        }
        wrappingKeys = InstrumentationWrappingKeys()
        context.deleteSharedPreferences(PIN_THROTTLE_PREFERENCES)
    }

    @After
    fun tearDown() {
        if (::context.isInitialized) {
            context.deleteSharedPreferences(PIN_THROTTLE_PREFERENCES)
        }
        if (::sandboxRoot.isInitialized) {
            assertTrue(sandboxRoot.deleteRecursively())
        }
    }

    @Test
    fun provisionConfigureLockAndPinUnlockSurviveManagerRecreation() {
        val firstManager = manager()
        val provisioned = BlockingNativeResult<NativeUnlockMaterial>()
        firstManager.provisionWithSystemAuth("Provision test keyring", provisioned)
        val original = provisioned.awaitValue()
        val expectedDatabaseKey = original.databaseKey.clone()
        val expectedFieldKey = original.fieldKey.clone()
        original.zeroize()

        val configured = BlockingNativeResult<Unit>()
        firstManager.configurePin(
            "Configure test PIN",
            TEST_PIN.toByteArray(),
            configured,
        )
        configured.awaitValue()
        firstManager.lock()
        firstManager.close()

        val restartedManager = manager()
        val state = restartedManager.getSecurityState()
        assertEquals(SecurityStatus.LOCKED, state.status)
        assertTrue(state.pinConfigured)
        val unlocked = BlockingNativeResult<NativeUnlockMaterial>()
        restartedManager.unlockWithPin(TEST_PIN.toByteArray(), unlocked)
        val restored = unlocked.awaitValue()

        assertEquals("pin", restored.unlockMethod)
        assertArrayEquals(expectedDatabaseKey, restored.databaseKey)
        assertArrayEquals(expectedFieldKey, restored.fieldKey)

        restored.zeroize()
        expectedDatabaseKey.fill(0)
        expectedFieldKey.fill(0)
        restartedManager.close()
    }

    @Test
    fun pinCooldownRemainsEnforcedAfterManagerRecreation() {
        val firstManager = manager()
        val provisioned = BlockingNativeResult<NativeUnlockMaterial>()
        firstManager.provisionWithSystemAuth("Provision throttle keyring", provisioned)
        provisioned.awaitValue().zeroize()
        val configured = BlockingNativeResult<Unit>()
        firstManager.configurePin(
            "Configure throttle PIN",
            TEST_PIN.toByteArray(),
            configured,
        )
        configured.awaitValue()

        repeat(PersistentPinAttemptThrottle.FAILURE_THRESHOLD) {
            val rejected = BlockingNativeResult<NativeUnlockMaterial>()
            firstManager.unlockWithPin("0000".toByteArray(), rejected)
            assertEquals(
                NativeSecurityErrorCode.PIN_INCORRECT,
                rejected.awaitError().code,
            )
        }
        firstManager.close()

        val restartedManager = manager()
        val blocked = BlockingNativeResult<NativeUnlockMaterial>()
        restartedManager.unlockWithPin(TEST_PIN.toByteArray(), blocked)

        assertEquals(
            NativeSecurityErrorCode.PIN_COOLDOWN,
            blocked.awaitError().code,
        )
        restartedManager.close()
    }

    private fun manager(): NativeKeyringManager {
        return NativeKeyringManager(
            apiLevel = android.os.Build.VERSION.SDK_INT,
            envelopeStore = AtomicFileSecurityEnvelopeStore(isolatedContext),
            legacyDetector = NoLegacySecurityDetector,
            wrappingKeys = wrappingKeys,
            authenticator = ImmediateSystemAuthenticator,
            capabilities = {
                SystemAuthCapabilities(
                    deviceCredentialAvailable = true,
                    strongBiometricAvailable = true,
                )
            },
            pinKdfEngine = Argon2KtPinKdfEngine(),
            pinThrottle = PersistentPinAttemptThrottle(
                store = SharedPreferencesPinThrottleStore(context),
                clock = AndroidPinThrottleClock(context),
            ),
        )
    }

    private companion object {
        const val TEST_PIN = "2468"
        const val PIN_THROTTLE_PREFERENCES = "native_security_pin_throttle"
    }
}

private object NoLegacySecurityDetector : LegacySecurityDetector {
    override fun hasLegacyPassword(): Boolean = false

    override fun readLegacyPassword(): String? = null

    override fun clearLegacyPassword(): Boolean = true
}

private object ImmediateSystemAuthenticator : SystemAuthenticator {
    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        terminal.succeeded(request.cipher)
    }

    override fun cancel(operationId: Long) = Unit
}

private class InstrumentationWrappingKeys : WrappingKeyRepository {
    private val keys = linkedMapOf<String, Key>()

    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
    ): WrappingKeyHandle {
        val key = SecretKeySpec(SecureRandomSource().bytes(32), "AES")
        keys[alias] = key
        return handle(alias, key)
    }

    override fun load(alias: String): WrappingKeyHandle? {
        return keys[alias]?.let { handle(alias, it) }
    }

    override fun delete(alias: String) {
        keys.remove(alias)
    }

    private fun handle(alias: String, key: Key): WrappingKeyHandle {
        return object : WrappingKeyHandle {
            override val alias = alias
            override val securityLevel = KeySecurityLevel.SOFTWARE

            override fun encryptionCipher(): Cipher {
                return Cipher.getInstance("AES/GCM/NoPadding").apply {
                    init(Cipher.ENCRYPT_MODE, key)
                }
            }

            override fun decryptionCipher(nonce: ByteArray): Cipher {
                return Cipher.getInstance("AES/GCM/NoPadding").apply {
                    init(
                        Cipher.DECRYPT_MODE,
                        key,
                        GCMParameterSpec(128, nonce),
                    )
                }
            }
        }
    }
}

private class BlockingNativeResult<T> : NativeResult<T> {
    private val completed = CountDownLatch(1)

    @Volatile
    private var value: T? = null

    @Volatile
    private var error: NativeSecurityException? = null

    override fun success(value: T) {
        this.value = value
        completed.countDown()
    }

    override fun error(error: NativeSecurityException) {
        this.error = error
        completed.countDown()
    }

    fun awaitValue(): T {
        awaitCompletion()
        error?.let { throw AssertionError("Unexpected security error: ${it.code}") }
        return checkNotNull(value)
    }

    fun awaitError(): NativeSecurityException {
        awaitCompletion()
        return checkNotNull(error)
    }

    private fun awaitCompletion() {
        assertTrue(
            "Timed out waiting for native security operation.",
            completed.await(2, TimeUnit.MINUTES),
        )
    }
}
