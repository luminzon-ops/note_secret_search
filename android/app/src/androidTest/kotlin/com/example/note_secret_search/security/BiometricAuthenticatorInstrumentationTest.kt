package com.example.note_secret_search.security

import androidx.biometric.BiometricManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.note_secret_search.BiometricAuthenticator
import com.example.note_secret_search.MainActivity
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BiometricAuthenticatorInstrumentationTest {
    private lateinit var alias: String
    private lateinit var wrappingKeys: WrappingKeyRepository
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var authenticator: BiometricAuthenticator

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(
            BiometricManager.BIOMETRIC_SUCCESS,
            BiometricManager.from(context).canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG,
            ),
        )
        alias = "nss-instrumentation-biometric-${UUID.randomUUID()}"
        wrappingKeys = AndroidWrappingKeyRepository(
            apiLevel = android.os.Build.VERSION.SDK_INT,
            backend = AndroidKeystoreWrappingKeyBackend(),
        )
        wrappingKeys.delete(alias)
        scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { activity ->
            authenticator = BiometricAuthenticator(activity)
        }
    }

    @After
    fun tearDown() {
        if (::authenticator.isInitialized) {
            authenticator.cancel(FIRST_OPERATION_ID)
            authenticator.cancel(SECOND_OPERATION_ID)
        }
        if (::scenario.isInitialized) {
            scenario.close()
        }
        if (::wrappingKeys.isInitialized && ::alias.isInitialized) {
            wrappingKeys.delete(alias)
        }
    }

    @Test
    fun authBoundPromptCancellationIsScopedToItsOperation() {
        val handle = wrappingKeys.create(
            alias,
            WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE,
        )
        val first = RecordingAuthenticationTerminal()
        val firstCipher = handle.encryptionCipher()

        scenario.onActivity {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason = "Verify first operation",
                    mode = SystemAuthenticatorMode.BIOMETRIC,
                    cipher = firstCipher,
                    operationId = FIRST_OPERATION_ID,
                ),
                first,
            )
            authenticator.cancel(SECOND_OPERATION_ID)
        }

        assertFalse(first.completed.await(500, TimeUnit.MILLISECONDS))
        scenario.onActivity {
            authenticator.cancel(FIRST_OPERATION_ID)
        }
        assertTrue(first.completed.await(5, TimeUnit.SECONDS))
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, first.error?.code)

        val second = RecordingAuthenticationTerminal()
        val secondCipher = handle.encryptionCipher()
        scenario.onActivity {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason = "Verify second operation",
                    mode = SystemAuthenticatorMode.BIOMETRIC,
                    cipher = secondCipher,
                    operationId = SECOND_OPERATION_ID,
                ),
                second,
            )
            authenticator.cancel(SECOND_OPERATION_ID)
        }

        assertTrue(second.completed.await(5, TimeUnit.SECONDS))
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, second.error?.code)
        assertNotNull(firstCipher.iv)
        assertNotNull(secondCipher.iv)
    }

    private companion object {
        const val FIRST_OPERATION_ID = 101L
        const val SECOND_OPERATION_ID = 102L
    }
}

private class RecordingAuthenticationTerminal : AuthenticationTerminal {
    val completed = CountDownLatch(1)

    @Volatile
    var error: NativeSecurityException? = null

    override fun succeeded(cipher: Cipher?) {
        completed.countDown()
    }

    override fun failed(error: NativeSecurityException) {
        this.error = error
        completed.countDown()
    }
}
