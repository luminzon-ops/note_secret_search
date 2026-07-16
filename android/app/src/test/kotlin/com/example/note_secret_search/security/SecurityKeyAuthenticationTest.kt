package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class SecurityKeyAuthenticationTest {
    @Test
    fun `biometric mismatch is non terminal`() {
        val terminal = RecordingAuthTerminal()
        val dispatcher = AuthenticationResultDispatcher(terminal)

        dispatcher.onAuthenticationFailed()

        assertFalse(terminal.completed)
    }

    @Test
    fun `user cancellation maps to stable cancellation error`() {
        val terminal = RecordingAuthTerminal()
        val dispatcher = AuthenticationResultDispatcher(terminal)

        dispatcher.onAuthenticationError(AuthPromptError.USER_CANCELED)

        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, terminal.error?.code)
        assertNull(terminal.cipher)
    }

    @Test
    fun `lockout maps to stable lockout error`() {
        val terminal = RecordingAuthTerminal()
        val dispatcher = AuthenticationResultDispatcher(terminal)

        dispatcher.onAuthenticationError(AuthPromptError.LOCKOUT_PERMANENT)

        assertEquals(NativeSecurityErrorCode.AUTH_LOCKOUT, terminal.error?.code)
    }

    @Test
    fun `missing device credential maps to stable credential error`() {
        val terminal = RecordingAuthTerminal()
        val dispatcher = AuthenticationResultDispatcher(terminal)

        dispatcher.onAuthenticationError(AuthPromptError.NO_DEVICE_CREDENTIAL)

        assertEquals(
            NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
            terminal.error?.code,
        )
    }

    @Test
    fun `only the first terminal authentication result is delivered`() {
        val terminal = RecordingAuthTerminal()
        val dispatcher = AuthenticationResultDispatcher(terminal)

        dispatcher.onAuthenticationSucceeded(null)
        dispatcher.onAuthenticationError(AuthPromptError.SYSTEM_CANCELED)

        assertEquals(1, terminal.completionCount)
        assertNull(terminal.error)
    }
}

private class RecordingAuthTerminal : AuthenticationTerminal {
    var completed = false
    var completionCount = 0
    var cipher: javax.crypto.Cipher? = null
    var error: NativeSecurityException? = null

    override fun succeeded(cipher: javax.crypto.Cipher?) {
        completed = true
        completionCount += 1
        this.cipher = cipher
    }

    override fun failed(error: NativeSecurityException) {
        completed = true
        completionCount += 1
        this.error = error
    }
}
