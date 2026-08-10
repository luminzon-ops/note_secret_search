package com.example.note_secret_search.security

import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher

interface RandomSource {
    fun bytes(size: Int): ByteArray
}

class SecureRandomSource(
    private val random: SecureRandom = SecureRandom(),
) : RandomSource {
    override fun bytes(size: Int): ByteArray {
        return ByteArray(size).also(random::nextBytes)
    }
}

internal object KeyringCrypto {
    const val MASTER_KEY_BYTES = 32
    private const val CIPHERTEXT_BYTES = 32
    private const val TAG_BYTES = 16

    fun randomUuid(random: RandomSource): String {
        val value = random.bytes(16)
        value[6] = ((value[6].toInt() and 0x0f) or 0x40).toByte()
        value[8] = ((value[8].toInt() and 0x3f) or 0x80).toByte()
        val buffer = ByteBuffer.wrap(value)
        return UUID(buffer.long, buffer.long).toString().also { value.fill(0) }
    }

    fun alias(keyId: String, kind: EnvelopeKind): String {
        return "note_secret_search.keyring.v2.$keyId.${kind.serializedName}"
    }

    fun wrap(
        keyId: String,
        kind: EnvelopeKind,
        alias: String,
        securityLevel: KeySecurityLevel,
        cipher: Cipher,
        masterKey: ByteArray,
    ): SecurityEnvelope {
        val metadata = SecurityEnvelope(
            kind = kind,
            keyAlias = alias,
            nonce = cipher.iv.clone(),
            ciphertext = ByteArray(CIPHERTEXT_BYTES),
            tag = ByteArray(TAG_BYTES),
            securityLevel = securityLevel,
        )
        cipher.updateAAD(SecurityEnvelopeAad.create(keyId, metadata))
        val wrapped = cipher.doFinal(masterKey)
        if (wrapped.size != CIPHERTEXT_BYTES + TAG_BYTES) {
            wrapped.fill(0)
            throw NativeSecurityException(NativeSecurityErrorCode.INTERNAL_ERROR)
        }
        return metadata.copy(
            ciphertext = wrapped.copyOfRange(0, CIPHERTEXT_BYTES),
            tag = wrapped.copyOfRange(CIPHERTEXT_BYTES, wrapped.size),
        ).also { wrapped.fill(0) }
    }

    fun unwrap(
        keyId: String,
        envelope: SecurityEnvelope,
        cipher: Cipher,
    ): ByteArray {
        val wrapped = ByteArray(CIPHERTEXT_BYTES + TAG_BYTES)
        envelope.ciphertext.copyInto(wrapped, 0)
        envelope.tag.copyInto(wrapped, CIPHERTEXT_BYTES)
        return try {
            cipher.updateAAD(SecurityEnvelopeAad.create(keyId, envelope))
            cipher.doFinal(wrapped)
        } finally {
            wrapped.fill(0)
        }
    }

    fun deriveMaterial(
        keyId: String,
        masterKey: ByteArray,
        unlockMethod: String = "system",
    ): NativeUnlockMaterial {
        return NativeUnlockMaterial(
            keyId = keyId,
            databaseKey = HkdfSha256.derive(masterKey, KeyDerivationLabels.DATABASE),
            fieldKey = HkdfSha256.derive(masterKey, KeyDerivationLabels.FIELD),
            searchIndexFingerprintKey = HkdfSha256.derive(
                masterKey,
                KeyDerivationLabels.SEARCH_INDEX_FINGERPRINT,
            ),
            unlockMethod = unlockMethod,
        )
    }

    fun cleanupAlias(
        wrappingKeys: WrappingKeyRepository,
        alias: String,
    ) {
        try {
            wrappingKeys.delete(alias)
        } catch (_: Throwable) {
            // Preserve the operation's primary stable error.
        }
    }

    fun mapKeyError(error: Throwable): NativeSecurityException {
        return when (error) {
            is NativeSecurityException -> error
            is WrappingKeyInvalidatedException -> NativeSecurityException(
                NativeSecurityErrorCode.KEY_INVALIDATED,
                error,
            )
            is KeystoreOperationFailure -> NativeSecurityException(
                NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE,
                error,
            )
            else -> NativeSecurityException(NativeSecurityErrorCode.INTERNAL_ERROR, error)
        }
    }

    fun mapUnlockError(error: Throwable): NativeSecurityException {
        return when (error) {
            is NativeSecurityException -> error
            is AEADBadTagException -> NativeSecurityException(
                NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                error,
            )
            is WrappingKeyInvalidatedException,
            is KeystoreOperationFailure,
            -> mapKeyError(error)
            else -> NativeSecurityException(
                NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                error,
            )
        }
    }
}
