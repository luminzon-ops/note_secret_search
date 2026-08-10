package com.example.note_secret_search.security

import java.security.InvalidAlgorithmParameterException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityKeyStrongBoxTest {
    @Test
    fun `api 28 requests StrongBox and records actual StrongBox success`() {
        val backend = RecordingWrappingKeyBackend(
            strongBoxLevel = KeySecurityLevel.STRONG_BOX,
        )
        val repository = AndroidWrappingKeyRepository(apiLevel = 28, backend = backend)

        val key = repository.create("alias", WrappingKeyPolicy.COMBINED_AUTH_PER_USE)

        assertEquals(listOf(true), backend.strongBoxRequests)
        assertEquals(KeySecurityLevel.STRONG_BOX, key.securityLevel)
    }

    @Test
    fun `explicit StrongBox unavailability retries once without claiming StrongBox`() {
        val backend = RecordingWrappingKeyBackend(
            strongBoxFailure = StrongBoxUnavailableFailure(),
            fallbackLevel = KeySecurityLevel.TEE,
        )
        val repository = AndroidWrappingKeyRepository(apiLevel = 30, backend = backend)

        val key = repository.create("alias", WrappingKeyPolicy.COMBINED_AUTH_PER_USE)

        assertEquals(listOf(true, false), backend.strongBoxRequests)
        assertEquals(KeySecurityLevel.TEE, key.securityLevel)
    }

    @Test(expected = KeystoreOperationFailure::class)
    fun `unrelated keystore failure does not trigger StrongBox fallback`() {
        val backend = RecordingWrappingKeyBackend(
            strongBoxFailure = KeystoreOperationFailure(),
        )
        val repository = AndroidWrappingKeyRepository(apiLevel = 30, backend = backend)

        repository.create("alias", WrappingKeyPolicy.COMBINED_AUTH_PER_USE)
    }

    @Test
    fun `invalid key specification is not classified as unsupported StrongBox`() {
        val classified = classifyKeyGenerationFailure(
            InvalidAlgorithmParameterException("invalid auth specification"),
        )

        assertTrue(classified is KeystoreOperationFailure)
    }
}

private class RecordingWrappingKeyBackend(
    private val strongBoxFailure: RuntimeException? = null,
    private val strongBoxLevel: KeySecurityLevel = KeySecurityLevel.STRONG_BOX,
    private val fallbackLevel: KeySecurityLevel = KeySecurityLevel.TEE,
) : WrappingKeyBackend {
    val strongBoxRequests = mutableListOf<Boolean>()

    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
        requestStrongBox: Boolean,
    ): WrappingKeyHandle {
        strongBoxRequests += requestStrongBox
        if (requestStrongBox) {
            strongBoxFailure?.let { throw it }
        }
        val level = if (requestStrongBox) strongBoxLevel else fallbackLevel
        return TestWrappingKeyHandle(
            alias = alias,
            securityLevel = level,
            key = javax.crypto.spec.SecretKeySpec(ByteArray(32), "AES"),
        )
    }

    override fun load(alias: String): WrappingKeyHandle? = null

    override fun delete(alias: String) {
    }
}
