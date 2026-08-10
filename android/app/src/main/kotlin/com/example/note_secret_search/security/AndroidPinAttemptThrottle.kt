package com.example.note_secret_search.security

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

internal class AndroidPinThrottleClock(
    private val context: Context,
) : PinThrottleClock {
    override fun now(): PinThrottleTime {
        return PinThrottleTime(
            elapsedRealtimeMs = SystemClock.elapsedRealtime(),
            bootCount = Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.BOOT_COUNT,
                UNKNOWN_BOOT_COUNT,
            ),
            wallClockMs = System.currentTimeMillis(),
        )
    }

    private companion object {
        const val UNKNOWN_BOOT_COUNT = -1
    }
}

internal class SharedPreferencesPinThrottleStore(
    context: Context,
) : PinThrottleStore {
    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    override fun read(): PinThrottleState? {
        if (!preferences.contains(VERSION_KEY)) {
            return null
        }
        return try {
            if (preferences.getInt(VERSION_KEY, 0) != VERSION) {
                unavailable()
            }
            PinThrottleState(
                pinGeneration = preferences.getString(
                    PIN_GENERATION_KEY,
                    null,
                ) ?: unavailable(),
                failureCount = preferences.getInt(FAILURE_COUNT_KEY, 0),
                observedElapsedRealtimeMs = preferences.getLong(
                    OBSERVED_ELAPSED_KEY,
                    -1,
                ),
                observedBootCount = preferences.getInt(
                    OBSERVED_BOOT_COUNT_KEY,
                    -1,
                ),
                observedWallClockMs = preferences.getLong(
                    OBSERVED_WALL_KEY,
                    -1,
                ),
                cooldownUntilElapsedRealtimeMs = preferences.getLong(
                    COOLDOWN_ELAPSED_KEY,
                    -1,
                ),
                cooldownUntilWallClockMs = preferences.getLong(
                    COOLDOWN_WALL_KEY,
                    -1,
                ),
            ).also(::validate)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: RuntimeException) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                error,
            )
        }
    }

    override fun write(state: PinThrottleState) {
        validate(state)
        persist {
            putInt(VERSION_KEY, VERSION)
            putString(PIN_GENERATION_KEY, state.pinGeneration)
            putInt(FAILURE_COUNT_KEY, state.failureCount)
            putLong(OBSERVED_ELAPSED_KEY, state.observedElapsedRealtimeMs)
            putInt(OBSERVED_BOOT_COUNT_KEY, state.observedBootCount)
            putLong(OBSERVED_WALL_KEY, state.observedWallClockMs)
            putLong(
                COOLDOWN_ELAPSED_KEY,
                state.cooldownUntilElapsedRealtimeMs,
            )
            putLong(COOLDOWN_WALL_KEY, state.cooldownUntilWallClockMs)
        }
    }

    override fun clear() {
        if (!preferences.contains(VERSION_KEY)) {
            return
        }
        persist {
            remove(VERSION_KEY)
            remove(PIN_GENERATION_KEY)
            remove(FAILURE_COUNT_KEY)
            remove(OBSERVED_ELAPSED_KEY)
            remove(OBSERVED_BOOT_COUNT_KEY)
            remove(OBSERVED_WALL_KEY)
            remove(COOLDOWN_ELAPSED_KEY)
            remove(COOLDOWN_WALL_KEY)
        }
    }

    private fun persist(
        edit: android.content.SharedPreferences.Editor.() -> Unit,
    ) {
        val persisted = try {
            preferences.edit().apply(edit).commit()
        } catch (error: RuntimeException) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                error,
            )
        }
        if (!persisted) {
            unavailable()
        }
    }

    private fun validate(state: PinThrottleState) {
        val validCooldown = if (
            state.failureCount >= PersistentPinAttemptThrottle.FAILURE_THRESHOLD
        ) {
            state.cooldownUntilElapsedRealtimeMs >=
                state.observedElapsedRealtimeMs &&
                state.cooldownUntilWallClockMs >= state.observedWallClockMs
        } else {
            state.cooldownUntilElapsedRealtimeMs == 0L &&
                state.cooldownUntilWallClockMs == 0L
        }
        if (state.failureCount <= 0 ||
            !PIN_GENERATION.matches(state.pinGeneration) ||
            state.observedElapsedRealtimeMs < 0 ||
            state.observedBootCount < -1 ||
            state.observedWallClockMs < 0 ||
            !validCooldown
        ) {
            unavailable()
        }
    }

    private fun unavailable(): Nothing {
        throw NativeSecurityException(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
        )
    }

    private companion object {
        const val PREFERENCES_NAME = "native_security_pin_throttle"
        const val VERSION = 1
        const val VERSION_KEY = "version"
        const val PIN_GENERATION_KEY = "pin_generation"
        const val FAILURE_COUNT_KEY = "failure_count"
        const val OBSERVED_ELAPSED_KEY = "observed_elapsed_realtime_ms"
        const val OBSERVED_BOOT_COUNT_KEY = "observed_boot_count"
        const val OBSERVED_WALL_KEY = "observed_wall_clock_ms"
        const val COOLDOWN_ELAPSED_KEY = "cooldown_until_elapsed_realtime_ms"
        const val COOLDOWN_WALL_KEY = "cooldown_until_wall_clock_ms"
        val PIN_GENERATION = Regex("^[0-9a-f]{64}$")
    }
}
