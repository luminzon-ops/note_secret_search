package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

internal class PinAttemptThrottleTest {
    private val generation = "1".repeat(64)

    @Test
    fun `cooldown survives process recreation on the same boot`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock()
        val firstProcess = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            firstProcess.recordFailure(generation)
        }
        val restartedProcess = PersistentPinAttemptThrottle(store, clock)

        val error = assertThrows(NativeSecurityException::class.java) {
            restartedProcess.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `reboot uses wall clock while the cooldown remains active`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock()
        val throttle = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            throttle.recordFailure(generation)
        }
        clock.bootCount += 1
        clock.elapsedRealtimeMs = 500
        clock.wallClockMs += 30_000

        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `wall clock rollback after reboot cannot end cooldown`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock()
        val throttle = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            throttle.recordFailure(generation)
        }
        clock.bootCount += 1
        clock.elapsedRealtimeMs = 500
        clock.wallClockMs -= 120_000

        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `wall clock forward jump after reboot cannot end cooldown`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock()
        val throttle = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            throttle.recordFailure(generation)
        }
        clock.bootCount += 1
        clock.elapsedRealtimeMs = 500
        clock.wallClockMs += 600_000

        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `failed retry after cooldown starts a fresh cooldown window`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock()
        val throttle = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            throttle.recordFailure(generation)
        }
        clock.elapsedRealtimeMs += 60_000
        clock.wallClockMs += 60_000
        throttle.checkAllowed(generation)

        throttle.recordFailure(generation)

        assertEquals(6, store.state?.failureCount)
        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }
        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `unknown boot count requires both clocks to leave cooldown`() {
        val store = FakePinThrottleStore().apply {
            state = PinThrottleState(
                pinGeneration = generation,
                failureCount = 5,
                observedElapsedRealtimeMs = 10_000,
                observedBootCount = -1,
                observedWallClockMs = 1_000_000,
                cooldownUntilElapsedRealtimeMs = 70_000,
                cooldownUntilWallClockMs = 1_060_000,
            )
        }
        val clock = FakePinThrottleClock(
            elapsedRealtimeMs = 11_000,
            bootCount = -1,
            wallClockMs = 1_061_000,
        )
        val throttle = PersistentPinAttemptThrottle(store, clock)

        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
    }

    @Test
    fun `unknown boot count reanchors cooldown after monotonic clock reset`() {
        val store = FakePinThrottleStore()
        val clock = FakePinThrottleClock(
            elapsedRealtimeMs = 5 * 24 * 60 * 60 * 1_000L,
            bootCount = -1,
            wallClockMs = 1_000_000,
        )
        val throttle = PersistentPinAttemptThrottle(store, clock)
        repeat(5) {
            throttle.recordFailure(generation)
        }
        clock.elapsedRealtimeMs = 500
        clock.wallClockMs += 30_000

        val error = assertThrows(NativeSecurityException::class.java) {
            throttle.checkAllowed(generation)
        }

        assertEquals(NativeSecurityErrorCode.PIN_COOLDOWN, error.code)
        assertEquals(500L, store.state?.observedElapsedRealtimeMs)
        assertEquals(60_500L, store.state?.cooldownUntilElapsedRealtimeMs)

        clock.elapsedRealtimeMs += 60_000
        clock.wallClockMs += 60_000
        throttle.checkAllowed(generation)
    }
}
