package com.example.note_secret_search.security

import javax.crypto.Cipher

enum class WrappingKeyPolicy {
    COMBINED_AUTH_PER_USE,
    DEVICE_CREDENTIAL_WINDOW,
    BIOMETRIC_AUTH_PER_USE,
}

interface WrappingKeyHandle {
    val alias: String
    val securityLevel: KeySecurityLevel

    fun encryptionCipher(): Cipher

    fun decryptionCipher(nonce: ByteArray): Cipher
}

interface WrappingKeyRepository {
    fun create(alias: String, policy: WrappingKeyPolicy): WrappingKeyHandle

    fun load(alias: String): WrappingKeyHandle?

    fun delete(alias: String)
}

interface WrappingKeyBackend {
    fun create(
        alias: String,
        policy: WrappingKeyPolicy,
        requestStrongBox: Boolean,
    ): WrappingKeyHandle

    fun load(alias: String): WrappingKeyHandle?

    fun delete(alias: String)
}

class StrongBoxUnavailableFailure(
    cause: Throwable? = null,
) : RuntimeException(cause)

class KeystoreOperationFailure(
    cause: Throwable? = null,
) : RuntimeException(cause)

class WrappingKeyInvalidatedException(
    cause: Throwable? = null,
) : RuntimeException(cause)

class AndroidWrappingKeyRepository(
    private val apiLevel: Int,
    private val backend: WrappingKeyBackend,
) : WrappingKeyRepository {
    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
    ): WrappingKeyHandle {
        if (apiLevel < 28) {
            return backend.create(alias, policy, requestStrongBox = false)
        }
        return try {
            backend.create(alias, policy, requestStrongBox = true)
        } catch (_: StrongBoxUnavailableFailure) {
            backend.create(alias, policy, requestStrongBox = false)
        }
    }

    override fun load(alias: String): WrappingKeyHandle? {
        return backend.load(alias)
    }

    override fun delete(alias: String) {
        backend.delete(alias)
    }
}
