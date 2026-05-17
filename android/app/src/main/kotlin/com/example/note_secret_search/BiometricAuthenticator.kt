package com.example.note_secret_search

import android.app.Activity
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class BiometricAuthenticator(
    activity: Activity,
) {
    private val hostActivity = activity as androidx.fragment.app.FragmentActivity
    private val executor = ContextCompat.getMainExecutor(activity)

    fun authenticate(reason: String, result: MethodChannel.Result) {
        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle("解锁 Note Secret Search")
            .setSubtitle(reason)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            promptInfoBuilder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            promptInfoBuilder.setNegativeButtonText("取消")
        }

        val promptInfo = promptInfoBuilder.build()

        val prompt = BiometricPrompt(
            hostActivity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(resultInfo: BiometricPrompt.AuthenticationResult) {
                    result.success(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    result.success(false)
                }

                override fun onAuthenticationFailed() {
                    result.success(false)
                }
            },
        )

        prompt.authenticate(promptInfo)
    }
}
