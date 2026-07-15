package com.example.note_secret_search.security

import javax.crypto.Cipher

enum class SystemAuthenticatorMode {
    COMBINED,
    DEVICE_CREDENTIAL,
    BIOMETRIC,
}

data class SystemAuthRequest(
    val reason: String,
    val mode: SystemAuthenticatorMode,
    val cipher: Cipher? = null,
)

interface SystemAuthenticator {
    fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    )

    fun cancel()
}

interface AuthenticationTerminal {
    fun succeeded(cipher: Cipher?)

    fun failed(error: NativeSecurityException)
}

enum class AuthPromptError {
    USER_CANCELED,
    NEGATIVE_BUTTON,
    SYSTEM_CANCELED,
    LOCKOUT,
    LOCKOUT_PERMANENT,
    NO_DEVICE_CREDENTIAL,
    OTHER,
}

class AuthenticationResultDispatcher(
    private val terminal: AuthenticationTerminal,
) {
    fun onAuthenticationSucceeded(cipher: Cipher?) {
        terminal.succeeded(cipher)
    }

    fun onAuthenticationError(error: AuthPromptError) {
        val code = when (error) {
            AuthPromptError.USER_CANCELED,
            AuthPromptError.NEGATIVE_BUTTON,
            AuthPromptError.SYSTEM_CANCELED,
            -> NativeSecurityErrorCode.AUTH_CANCELLED

            AuthPromptError.LOCKOUT,
            AuthPromptError.LOCKOUT_PERMANENT,
            -> NativeSecurityErrorCode.AUTH_LOCKOUT

            AuthPromptError.NO_DEVICE_CREDENTIAL ->
                NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET

            AuthPromptError.OTHER -> NativeSecurityErrorCode.AUTH_FAILED
        }
        terminal.failed(NativeSecurityException(code))
    }

    fun onAuthenticationFailed() {
        // A biometric mismatch is advisory; Android may deliver a later success.
    }
}
