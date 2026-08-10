package com.example.note_secret_search

import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
import com.example.note_secret_search.security.NativeUnlockMaterial
import io.flutter.plugin.common.MethodChannel

internal fun channelResult(
    result: MethodChannel.Result,
): NativeResult<NativeUnlockMaterial> {
    return object : NativeResult<NativeUnlockMaterial> {
        override fun success(value: NativeUnlockMaterial) {
            try {
                result.success(value.toChannelMap())
            } finally {
                value.zeroize()
            }
        }

        override fun error(error: NativeSecurityException) {
            sendError(result, error)
        }
    }
}

internal fun unitChannelResult(
    result: MethodChannel.Result,
): NativeResult<Unit> {
    return object : NativeResult<Unit> {
        override fun success(value: Unit) {
            result.success(null)
        }

        override fun error(error: NativeSecurityException) {
            sendError(result, error)
        }
    }
}

internal fun sanitizeSecurityError(error: Throwable): NativeSecurityException {
    return error as? NativeSecurityException
        ?: NativeSecurityException(
            NativeSecurityErrorCode.INTERNAL_ERROR,
            error,
        )
}

internal fun sendError(
    result: MethodChannel.Result,
    error: NativeSecurityException,
) {
    result.error(error.code.name, error.message, null)
}
