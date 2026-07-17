package com.example.note_secret_search.security

import java.security.MessageDigest

internal data class PinThrottleTime(
    val elapsedRealtimeMs: Long,
    val bootCount: Int,
    val wallClockMs: Long,
)

internal data class PinThrottleState(
    val pinGeneration: String,
    val failureCount: Int,
    val observedElapsedRealtimeMs: Long,
    val observedBootCount: Int,
    val observedWallClockMs: Long,
    val cooldownUntilElapsedRealtimeMs: Long,
    val cooldownUntilWallClockMs: Long,
)

internal interface PinThrottleStore {
    fun read(): PinThrottleState?

    fun write(state: PinThrottleState)

    fun clear()
}

internal fun interface PinThrottleClock {
    fun now(): PinThrottleTime
}

internal interface PinAttemptThrottle {
    fun checkAllowed(pinGeneration: String)

    fun recordFailure(pinGeneration: String)

    fun recordSuccess(pinGeneration: String)
}

internal class PersistentPinAttemptThrottle(
    private val store: PinThrottleStore,
    private val clock: PinThrottleClock,
) : PinAttemptThrottle {
    override fun checkAllowed(pinGeneration: String) {
        val state = store.read() ?: return
        if (state.pinGeneration != pinGeneration ||
            state.failureCount < FAILURE_THRESHOLD
        ) {
            return
        }
        val now = clock.now()
        val bootCountsKnown = state.observedBootCount >= 0 &&
            now.bootCount >= 0
        val rebootDetected =
            bootCountsKnown && state.observedBootCount != now.bootCount
        val monotonicClockResetWithoutBootCount =
            !bootCountsKnown &&
                now.elapsedRealtimeMs < state.observedElapsedRealtimeMs
        if (rebootDetected || monotonicClockResetWithoutBootCount) {
            store.write(
                state.copy(
                    observedElapsedRealtimeMs = now.elapsedRealtimeMs,
                    observedBootCount = now.bootCount,
                    observedWallClockMs = now.wallClockMs,
                    cooldownUntilElapsedRealtimeMs = saturatedAdd(
                        now.elapsedRealtimeMs,
                        COOLDOWN_MS,
                    ),
                    cooldownUntilWallClockMs = saturatedAdd(
                        now.wallClockMs,
                        COOLDOWN_MS,
                    ),
                ),
            )
            throwPinCooldown()
        }
        val elapsedCoolingDown =
            now.elapsedRealtimeMs < state.observedElapsedRealtimeMs ||
                now.elapsedRealtimeMs < state.cooldownUntilElapsedRealtimeMs
        val wallCoolingDown = now.wallClockMs < state.observedWallClockMs ||
            now.wallClockMs < state.cooldownUntilWallClockMs
        val coolingDown = when {
            bootCountsKnown &&
                state.observedBootCount == now.bootCount -> elapsedCoolingDown
            bootCountsKnown -> wallCoolingDown
            else -> elapsedCoolingDown || wallCoolingDown
        }
        if (coolingDown) {
            throwPinCooldown()
        }
    }

    override fun recordFailure(pinGeneration: String) {
        val previous = store.read()?.takeIf {
            it.pinGeneration == pinGeneration
        }
        val failureCount = (previous?.failureCount ?: 0)
            .coerceAtMost(Int.MAX_VALUE - 1) + 1
        val now = clock.now()
        val cooldownRequired = failureCount >= FAILURE_THRESHOLD
        store.write(
            PinThrottleState(
                pinGeneration = pinGeneration,
                failureCount = failureCount,
                observedElapsedRealtimeMs = now.elapsedRealtimeMs,
                observedBootCount = now.bootCount,
                observedWallClockMs = now.wallClockMs,
                cooldownUntilElapsedRealtimeMs = if (cooldownRequired) {
                    saturatedAdd(now.elapsedRealtimeMs, COOLDOWN_MS)
                } else {
                    0
                },
                cooldownUntilWallClockMs = if (cooldownRequired) {
                    saturatedAdd(now.wallClockMs, COOLDOWN_MS)
                } else {
                    0
                },
            ),
        )
    }

    override fun recordSuccess(pinGeneration: String) {
        store.clear()
    }

    private fun saturatedAdd(value: Long, increment: Long): Long {
        return if (value > Long.MAX_VALUE - increment) {
            Long.MAX_VALUE
        } else {
            value + increment
        }
    }

    private fun throwPinCooldown(): Nothing {
        throw NativeSecurityException(
            NativeSecurityErrorCode.PIN_COOLDOWN,
        )
    }

    companion object {
        const val FAILURE_THRESHOLD = 5
        const val COOLDOWN_MS = 60_000L
    }
}

internal object PinEnvelopeGeneration {
    fun create(
        keyId: String,
        envelope: PinEnvelope,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(PinEnvelopeAad.create(keyId, envelope.kdf))
        digest.update(envelope.nonce)
        digest.update(envelope.ciphertext)
        digest.update(envelope.tag)
        return digest.digest().joinToString(separator = "") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
    }
}
