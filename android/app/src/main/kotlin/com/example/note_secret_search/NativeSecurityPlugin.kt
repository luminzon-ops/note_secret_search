package com.example.note_secret_search

import android.app.Activity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.biometric.BiometricManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeSecurityPlugin(
    private val activity: Activity,
    private val recentTaskShieldView: FrameLayout,
) : MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val keyManager = SecureKeyManager(activity)
    private val biometricAuthenticator = BiometricAuthenticator(activity)

    fun attachToEngine(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
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

            "ensureRootKey" -> {
                keyManager.ensureRootKey()
                result.success(null)
            }

            "getDatabasePasswordMaterial" -> {
                result.success(keyManager.getDatabasePasswordMaterial())
            }

            "getBiometricAvailability" -> {
                val availability = when (
                    BiometricManager.from(activity).canAuthenticate(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                    )
                ) {
                    BiometricManager.BIOMETRIC_SUCCESS -> "available"
                    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "not_enrolled"
                    else -> "unavailable"
                }
                result.success(availability)
            }

            "authenticateWithBiometrics" -> {
                biometricAuthenticator.authenticate(
                    reason = call.argument<String>("reason") ?: "解锁保险库",
                    result = result,
                )
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/native_security"
    }
}
