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
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
import com.example.note_secret_search.security.SystemAuthRequest
import com.example.note_secret_search.security.SystemAuthenticator
import com.example.note_secret_search.security.SystemAuthenticatorMode
import io.flutter.plugin.common.MethodChannel

class BiometricAuthenticator(
    private val activity: Activity,
) : SystemAuthenticator, LegacyBiometricOperations {
    private val hostActivity = activity as FragmentActivity
    private val executor = ContextCompat.getMainExecutor(activity)
    private val sessions = BiometricAuthenticationSessionGate()
    private var activePrompt: BiometricPrompt? = null
    private var activePromptSession: BiometricAuthenticationSession? = null
    private var promptLostWindowFocus = false
    private var focusRecoveryGeneration = 0L

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        hostActivity.runOnUiThread {
            val dispatcher = AuthenticationResultDispatcher(terminal)
            val session = sessions.begin(request.operationId) {
                dispatcher.onAuthenticationError(AuthPromptError.SYSTEM_CANCELED)
            }
            if (session == null) {
                terminal.failed(NativeSecurityException(NativeSecurityErrorCode.BUSY))
                return@runOnUiThread
            }
            try {
                val prompt = BiometricPrompt(
                    hostActivity,
                    executor,
                    callback(request, dispatcher, session),
                )
                activePrompt = prompt
                activePromptSession = session
                promptLostWindowFocus = false
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
            } catch (error: Throwable) {
                if (sessions.complete(session)) {
                    clearActivePrompt(session)
                }
                terminal.failed(
                    error as? NativeSecurityException
                        ?: NativeSecurityException(
                            NativeSecurityErrorCode.AUTH_FAILED,
                            error,
                        ),
                )
            }
        }
    }

    override fun cancel(operationId: Long) {
        hostActivity.runOnUiThread {
            sessions.cancel(operationId) {
                val prompt = activePrompt
                clearActivePrompt()
                prompt?.cancelAuthentication()
            }
        }
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        hostActivity.runOnUiThread {
            val session = activePromptSession ?: return@runOnUiThread
            val prompt = activePrompt ?: return@runOnUiThread
            if (!hasFocus) {
                promptLostWindowFocus = true
                focusRecoveryGeneration += 1
                return@runOnUiThread
            }
            if (!promptLostWindowFocus) {
                return@runOnUiThread
            }
            val generation = ++focusRecoveryGeneration
            hostActivity.window.decorView.postDelayed({
                if (
                    generation != focusRecoveryGeneration ||
                    activePrompt !== prompt ||
                    activePromptSession !== session ||
                    !sessions.isActive(session) ||
                    !hostActivity.hasWindowFocus()
                ) {
                    return@postDelayed
                }
                sessions.cancelSession(session) {
                    clearActivePrompt(session)
                    prompt.cancelAuthentication()
                }
            }, PROMPT_DISMISS_GRACE_MILLIS)
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
        session: BiometricAuthenticationSession,
    ): BiometricPrompt.AuthenticationCallback {
        return object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                result: BiometricPrompt.AuthenticationResult,
            ) {
                if (sessions.complete(session)) {
                    clearActivePrompt(session)
                    dispatcher.onAuthenticationSucceeded(
                        result.cryptoObject?.cipher ?: request.cipher,
                    )
                }
            }

            override fun onAuthenticationError(
                errorCode: Int,
                errString: CharSequence,
            ) {
                if (sessions.complete(session)) {
                    clearActivePrompt(session)
                    dispatcher.onAuthenticationError(mapPromptError(errorCode))
                }
            }

            override fun onAuthenticationFailed() {
                dispatcher.onAuthenticationFailed()
            }
        }
    }

    private fun clearActivePrompt(
        session: BiometricAuthenticationSession? = null,
    ) {
        if (session != null && activePromptSession !== session) {
            return
        }
        activePrompt = null
        activePromptSession = null
        promptLostWindowFocus = false
        focusRecoveryGeneration += 1
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

    private companion object {
        const val PROMPT_DISMISS_GRACE_MILLIS = 500L
    }
}

internal data class BiometricAuthenticationSession(
    val operationId: Long,
    val onCancel: () -> Unit,
    val token: Any = Any(),
)

internal class BiometricAuthenticationSessionGate {
    private val lock = Any()
    private var active: BiometricAuthenticationSession? = null

    fun begin(
        operationId: Long,
        onCancel: () -> Unit = {},
    ): BiometricAuthenticationSession? {
        return synchronized(lock) {
            if (active != null) {
                return@synchronized null
            }
            BiometricAuthenticationSession(operationId, onCancel).also {
                active = it
            }
        }
    }

    fun complete(session: BiometricAuthenticationSession): Boolean {
        return synchronized(lock) {
            if (active !== session) {
                return@synchronized false
            }
            active = null
            true
        }
    }

    fun isActive(session: BiometricAuthenticationSession): Boolean {
        return synchronized(lock) { active === session }
    }

    fun cancelSession(
        session: BiometricAuthenticationSession,
        beforeNotify: () -> Unit = {},
    ): Boolean {
        val claimed = synchronized(lock) {
            if (active !== session) {
                return@synchronized null
            }
            active = null
            session
        }
        try {
            beforeNotify()
        } catch (_: Throwable) {
            // A detached vendor prompt must not block app-side cancellation.
        }
        try {
            claimed?.onCancel?.invoke()
        } catch (_: Throwable) {
            // Result transports may already be gone during activity teardown.
        }
        return claimed != null
    }

    fun cancel(
        operationId: Long,
        beforeNotify: () -> Unit = {},
    ): Boolean {
        val session = synchronized(lock) {
            if (active?.operationId != operationId) {
                return false
            }
            val claimed = active
            active = null
            claimed
        }
        try {
            beforeNotify()
        } catch (_: Throwable) {
            // A detached vendor prompt must not block app-side cancellation.
        }
        try {
            session?.onCancel?.invoke()
        } catch (_: Throwable) {
            // Result transports may already be gone during activity teardown.
        }
        return true
    }
}
