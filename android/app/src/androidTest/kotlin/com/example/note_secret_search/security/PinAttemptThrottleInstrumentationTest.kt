package com.example.note_secret_search.security

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PinAttemptThrottleInstrumentationTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        context.deleteSharedPreferences(PREFERENCES_NAME)
    }

    @After
    fun tearDown() {
        if (::context.isInitialized) {
            context.deleteSharedPreferences(PREFERENCES_NAME)
        }
    }

    @Test
    fun cooldownPersistsAcrossStoreRecreationAndSuccessClearsIt() {
        val firstProcess = throttle()
        repeat(PersistentPinAttemptThrottle.FAILURE_THRESHOLD) {
            firstProcess.recordFailure(PIN_GENERATION)
        }

        val restartedProcess = throttle()
        val blocked = assertThrows(NativeSecurityException::class.java) {
            restartedProcess.checkAllowed(PIN_GENERATION)
        }
        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, blocked.code)

        restartedProcess.recordSuccess(PIN_GENERATION)
        throttle().checkAllowed(PIN_GENERATION)
    }

    @Test
    fun corruptPersistedStateFailsClosed() {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt("version", 1)
            .putString("pin_generation", "invalid")
            .putInt("failure_count", 5)
            .putLong("observed_elapsed_realtime_ms", 1)
            .putInt("observed_boot_count", -1)
            .putLong("observed_wall_clock_ms", 1)
            .putLong("cooldown_until_elapsed_realtime_ms", 61_000)
            .putLong("cooldown_until_wall_clock_ms", 61_000)
            .commit()

        val error = assertThrows(NativeSecurityException::class.java) {
            SharedPreferencesPinThrottleStore(context).read()
        }

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            error.code,
        )
    }

    private fun throttle(): PersistentPinAttemptThrottle {
        return PersistentPinAttemptThrottle(
            store = SharedPreferencesPinThrottleStore(context),
            clock = AndroidPinThrottleClock(context),
        )
    }

    private companion object {
        const val PREFERENCES_NAME = "native_security_pin_throttle"
        val PIN_GENERATION = "1".repeat(64)
    }
}
