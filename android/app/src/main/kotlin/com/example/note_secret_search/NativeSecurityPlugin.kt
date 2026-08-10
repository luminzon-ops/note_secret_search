package com.example.note_secret_search

import android.app.Activity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
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
                val obscured = try {
                    requireRecentTaskObscured(
                        call.argument<Any?>("obscured"),
                    )
                } catch (error: NativeSecurityException) {
                    activity.runOnUiThread {
                        recentTaskShieldView.visibility = View.VISIBLE
                    }
                    sendError(result, error)
                    return
                }
                activity.runOnUiThread {
                    recentTaskShieldView.visibility = if (obscured) View.VISIBLE else View.GONE
                }
                result.success(null)
            }

            "getSecurityState" -> {
                nativeSecurityMethodHandler.getSecurityState(result)
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

            "rebindSystemAuthWithPin" -> {
                nativeSecurityMethodHandler.rebindSystemAuthWithPin(
                    call.argument<Any?>("reason"),
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

            "beginLegacyMigration" -> {
                nativeSecurityMethodHandler.beginLegacyMigration(
                    call.argument<Any?>("reason"),
                    result,
                )
            }

            "getLegacyMigrationState" -> {
                nativeSecurityMethodHandler.getLegacyMigrationState(result)
            }

            "prepareLegacyMigrationBackup" -> {
                nativeSecurityMethodHandler.prepareLegacyMigrationBackup(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "prepareLegacyMigrationPending" -> {
                nativeSecurityMethodHandler.prepareLegacyMigrationPending(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "markLegacyMigrationRowsCopied" -> {
                nativeSecurityMethodHandler.markLegacyMigrationRowsCopied(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "markLegacyMigrationValidated" -> {
                nativeSecurityMethodHandler.markLegacyMigrationValidated(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "activateLegacyMigration" -> {
                nativeSecurityMethodHandler.activateLegacyMigration(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "markLegacyMigrationPostSwapValidated" -> {
                nativeSecurityMethodHandler.markLegacyMigrationPostSwapValidated(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "cleanupLegacyMigrationFiles" -> {
                nativeSecurityMethodHandler.cleanupLegacyMigrationFiles(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "finishLegacyMigration" -> {
                nativeSecurityMethodHandler.finishLegacyMigration(
                    call.argument<Any?>("keyId"),
                    result,
                )
            }

            "commitLegacyMigration" -> {
                nativeSecurityMethodHandler.commitLegacyMigration(
                    call.argument<Any?>("keyId"),
                    call.argument<Any?>("activeDigest"),
                    result,
                )
            }

            "abortLegacyMigration" -> {
                nativeSecurityMethodHandler.abortLegacyMigration(result)
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

internal fun requireRecentTaskObscured(value: Any?): Boolean {
    return value as? Boolean
        ?: throw NativeSecurityException(
            NativeSecurityErrorCode.INVALID_ARGUMENT,
        )
}
