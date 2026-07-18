package com.example.note_secret_search

import io.flutter.plugin.common.MethodChannel

internal interface LegacyBiometricOperations {
    fun getBiometricAvailability(): String

    fun authenticateWithBiometrics(
        reason: String,
        result: MethodChannel.Result,
    )
}

internal class LegacyBiometricMethodHandler(
    private val operations: LegacyBiometricOperations,
) {
    fun getBiometricAvailability(result: MethodChannel.Result) {
        try {
            result.success(operations.getBiometricAvailability())
        } catch (_: Throwable) {
            result.success("unavailable")
        }
    }

    fun authenticateWithBiometrics(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        val resolvedReason = (reason as? String)
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_REASON
        try {
            operations.authenticateWithBiometrics(resolvedReason, result)
        } catch (_: Throwable) {
            result.success(false)
        }
    }

    companion object {
        private const val DEFAULT_REASON = "解锁保险库"
    }
}
