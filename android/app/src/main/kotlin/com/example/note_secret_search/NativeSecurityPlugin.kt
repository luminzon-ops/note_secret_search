package com.example.note_secret_search

import android.app.Activity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
import com.example.note_secret_search.security.NativeUnlockMaterial
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeSecurityPlugin(
    private val activity: Activity,
    private val recentTaskShieldView: FrameLayout,
) : MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val biometricAuthenticator = BiometricAuthenticator(activity)
    private val keyManager = SecureKeyManager(activity, biometricAuthenticator)
    private val nativeSecurityMethodHandler = NativeSecurityMethodHandler(keyManager)
    private val secureKeyMethodHandler = SecureKeyMethodHandler(keyManager)
    private val legacyBiometricMethodHandler =
        LegacyBiometricMethodHandler(biometricAuthenticator)

    fun attachToEngine(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    fun detachFromEngine() {
        if (this::channel.isInitialized) {
            channel.setMethodCallHandler(null)
        }
        keyManager.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableScreenshotProtection" -> {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                result.success(null)
            }

            "updateRecentTaskProtection" -> {
                val obscured = call.argument<Boolean>("obscured") ?: false
                activity.runOnUiThread {
                    recentTaskShieldView.visibility = if (obscured) View.VISIBLE else View.GONE
                }
                result.success(null)
            }

            "getSecurityState" -> {
                nativeSecurityMethodHandler.getSecurityState(result)
            }

            "ensureRootKey" -> {
                secureKeyMethodHandler.ensureRootKey(result)
            }

            "getDatabasePasswordMaterial" -> {
                secureKeyMethodHandler.getDatabasePasswordMaterial(result)
            }

            "getBiometricAvailability" -> {
                legacyBiometricMethodHandler.getBiometricAvailability(result)
            }

            "authenticateWithBiometrics" -> {
                legacyBiometricMethodHandler.authenticateWithBiometrics(
                    call.argument<Any?>("reason"),
                    result,
                )
            }

            "provisionWithSystemAuth" -> {
                nativeSecurityMethodHandler.provisionWithSystemAuth(
                    call.argument<Any?>("reason"),
                    result,
                )
            }

            "unlockWithSystemAuth" -> {
                nativeSecurityMethodHandler.unlockWithSystemAuth(
                    call.argument<Any?>("reason"),
                    result,
                )
            }

            "configurePin" -> {
                nativeSecurityMethodHandler.configurePin(
                    call.argument<Any?>("reason"),
                    call.argument<Any?>("pin"),
                    result,
                )
            }

            "unlockWithPin" -> {
                nativeSecurityMethodHandler.unlockWithPin(
                    call.argument<Any?>("pin"),
                    result,
                )
            }

            "removePin" -> {
                nativeSecurityMethodHandler.removePin(
                    call.argument<Any?>("reason"),
                    result,
                )
            }

            "lock" -> {
                nativeSecurityMethodHandler.lock(result)
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/native_security"
    }
}

internal class NativeSecurityMethodHandler(
    private val operations: NativeKeyringOperations,
) {
    fun getSecurityState(result: MethodChannel.Result) {
        handle(result) {
            operations.getSecurityState().toChannelMap()
        }
    }

    fun provisionWithSystemAuth(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.provisionWithSystemAuth(it, channelResult(result))
        }
    }

    fun unlockWithSystemAuth(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.unlockWithSystemAuth(it, channelResult(result))
        }
    }

    fun configurePin(
        reason: Any?,
        pin: Any?,
        result: MethodChannel.Result,
    ) {
        val ownedPin = pinBytes(pin, result) ?: return
        withReason(
            value = reason,
            result = result,
            rejected = { ownedPin.fill(0) },
        ) {
            operations.configurePin(it, ownedPin, unitChannelResult(result))
        }
    }

    fun unlockWithPin(
        pin: Any?,
        result: MethodChannel.Result,
    ) {
        val ownedPin = pinBytes(pin, result) ?: return
        try {
            operations.unlockWithPin(ownedPin, channelResult(result))
        } catch (error: Throwable) {
            ownedPin.fill(0)
            sendError(result, sanitize(error))
        }
    }

    fun removePin(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.removePin(it, unitChannelResult(result))
        }
    }

    fun lock(result: MethodChannel.Result) {
        handle(result) {
            operations.lock()
        }
    }

    private fun withReason(
        value: Any?,
        result: MethodChannel.Result,
        rejected: () -> Unit = {},
        operation: (String) -> Unit,
    ) {
        val reason = value as? String
        if (reason.isNullOrBlank()) {
            rejected()
            sendError(
                result,
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        try {
            operation(reason)
        } catch (error: Throwable) {
            rejected()
            sendError(result, sanitize(error))
        }
    }

    private fun pinBytes(
        value: Any?,
        result: MethodChannel.Result,
    ): ByteArray? {
        if (value is ByteArray) {
            return value
        }
        sendError(
            result,
            NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
        )
        return null
    }

    private fun channelResult(
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

    private fun unitChannelResult(
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

    private fun handle(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        try {
            result.success(operation())
        } catch (error: Throwable) {
            sendError(result, sanitize(error))
        }
    }

    private fun sanitize(error: Throwable): NativeSecurityException {
        return error as? NativeSecurityException
            ?: NativeSecurityException(
                NativeSecurityErrorCode.INTERNAL_ERROR,
                error,
            )
    }

    private fun sendError(
        result: MethodChannel.Result,
        error: NativeSecurityException,
    ) {
        result.error(error.code.name, error.message, null)
    }
}

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

internal class SecureKeyMethodHandler(
    private val operations: SecureKeyOperations,
) {
    fun ensureRootKey(result: MethodChannel.Result) {
        handle(result) {
            operations.ensureRootKey()
            null
        }
    }

    fun getDatabasePasswordMaterial(result: MethodChannel.Result) {
        handle(result) {
            operations.getDatabasePasswordMaterial()
        }
    }

    private fun handle(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        try {
            result.success(operation())
        } catch (_: Throwable) {
            result.error(
                "SECURE_KEY_UNAVAILABLE",
                "Secure key material is unavailable.",
                null,
            )
        }
    }
}
