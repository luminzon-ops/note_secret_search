package com.example.note_secret_search

import android.app.Activity
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.example.note_secret_search.security.AuthPromptError
import com.example.note_secret_search.security.AuthenticationResultDispatcher
import com.example.note_secret_search.security.AuthenticationTerminal
import com.example.note_secret_search.security.SystemAuthRequest
import com.example.note_secret_search.security.SystemAuthenticator
import com.example.note_secret_search.security.SystemAuthenticatorMode
import io.flutter.plugin.common.MethodChannel

class BiometricAuthenticator(
    private val activity: Activity,
) : SystemAuthenticator, LegacyBiometricOperations {
    private val hostActivity = activity as FragmentActivity
    private val executor = ContextCompat.getMainExecutor(activity)

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        hostActivity.runOnUiThread {
            val dispatcher = AuthenticationResultDispatcher(terminal)
            val prompt = BiometricPrompt(
                hostActivity,
                executor,
                callback(request, dispatcher),
            )
            val promptInfo = promptInfo(request)
            val cipher = request.cipher
            if (cipher == null) {
                prompt.authenticate(promptInfo)
            } else {
                prompt.authenticate(
                    promptInfo,
                    BiometricPrompt.CryptoObject(cipher),
                )
            }
        }
    }

    override fun getBiometricAvailability(): String {
        val authenticators = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        }
        return when (BiometricManager.from(activity).canAuthenticate(authenticators)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "not_enrolled"
            else -> "unavailable"
        }
    }

    override fun authenticateWithBiometrics(
        reason: String,
        result: MethodChannel.Result,
    ) {
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            SystemAuthenticatorMode.COMBINED
        } else {
            SystemAuthenticatorMode.BIOMETRIC
        }
        authenticate(
            SystemAuthRequest(reason = reason, mode = mode),
            object : AuthenticationTerminal {
                override fun succeeded(cipher: javax.crypto.Cipher?) {
                    result.success(true)
                }

                override fun failed(
                    error: com.example.note_secret_search.security.NativeSecurityException,
                ) {
                    result.success(false)
                }
            },
        )
    }

    private fun promptInfo(
        request: SystemAuthRequest,
    ): BiometricPrompt.PromptInfo {
        val builder = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock Note Secret Search")
            .setSubtitle(request.reason)
            .setConfirmationRequired(false)

        when (request.mode) {
            SystemAuthenticatorMode.COMBINED -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                            BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    builder.setDeviceCredentialAllowed(true)
                }
            }

            SystemAuthenticatorMode.DEVICE_CREDENTIAL -> {
                @Suppress("DEPRECATION")
                builder.setDeviceCredentialAllowed(true)
            }

            SystemAuthenticatorMode.BIOMETRIC -> {
                builder
                    .setAllowedAuthenticators(
                        BiometricManager.Authenticators.BIOMETRIC_STRONG,
                    )
                    .setNegativeButtonText("Cancel")
            }
        }
        return builder.build()
    }

    private fun callback(
        request: SystemAuthRequest,
        dispatcher: AuthenticationResultDispatcher,
    ): BiometricPrompt.AuthenticationCallback {
        return object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                result: BiometricPrompt.AuthenticationResult,
            ) {
                dispatcher.onAuthenticationSucceeded(
                    result.cryptoObject?.cipher ?: request.cipher,
                )
            }

            override fun onAuthenticationError(
                errorCode: Int,
                errString: CharSequence,
            ) {
                dispatcher.onAuthenticationError(mapPromptError(errorCode))
            }

            override fun onAuthenticationFailed() {
                dispatcher.onAuthenticationFailed()
            }
        }
    }

    private fun mapPromptError(errorCode: Int): AuthPromptError {
        return when (errorCode) {
            BiometricPrompt.ERROR_USER_CANCELED -> AuthPromptError.USER_CANCELED
            BiometricPrompt.ERROR_NEGATIVE_BUTTON -> AuthPromptError.NEGATIVE_BUTTON
            BiometricPrompt.ERROR_CANCELED -> AuthPromptError.SYSTEM_CANCELED
            BiometricPrompt.ERROR_LOCKOUT -> AuthPromptError.LOCKOUT
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                AuthPromptError.LOCKOUT_PERMANENT
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL ->
                AuthPromptError.NO_DEVICE_CREDENTIAL
            else -> AuthPromptError.OTHER
        }
    }
}
