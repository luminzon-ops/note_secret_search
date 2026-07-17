package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

@OptIn(ExperimentalEncodingApi::class)
internal object PinEnvelopeAad {
    fun create(
        keyId: String,
        kdf: PinKdfParameters,
    ): ByteArray {
        val value = buildString {
            append("note-secret-search/pin-envelope/v2\n")
            append("keyId=").append(keyId).append('\n')
            append("purpose=database-dek-pin\n")
            append("algorithm=").append(SecurityKeysetCodec.ALGORITHM).append('\n')
            append("kdf=").append(SecurityKeysetCodec.PIN_KDF_ALGORITHM).append('\n')
            append("memoryKiB=").append(kdf.memoryKiB).append('\n')
            append("iterations=").append(kdf.iterations).append('\n')
            append("parallelism=").append(kdf.parallelism).append('\n')
            append("outputBytes=").append(PinKeyDeriver.OUTPUT_BYTES).append('\n')
            append("salt=").append(Base64.encode(kdf.salt))
        }
        return value.toByteArray(StandardCharsets.UTF_8)
    }
}

internal class PreparedPinKey(
    val kdf: PinKdfParameters,
    val kek: ByteArray,
) {
    fun clear() {
        kek.fill(0)
    }
}

internal class PinEnvelopeCrypto(
    private val keyDeriver: PinKeyDeriver,
    private val random: RandomSource = SecureRandomSource(),
) {
    fun prepare(
        pin: ByteArray,
    ): PreparedPinKey {
        try {
            val kdf = PinKdfParameters(
                memoryKiB = PinKeyDeriver.MEMORY_KIB,
                iterations = PinKeyDeriver.ITERATIONS,
                parallelism = PinKeyDeriver.PARALLELISM,
                salt = random.bytes(PinKeyDeriver.SALT_BYTES),
            )
            return PreparedPinKey(
                kdf = kdf,
                kek = keyDeriver.derive(pin, kdf.salt),
            )
        } finally {
            pin.fill(0)
        }
    }

    fun wrap(
        keyId: String,
        masterKey: ByteArray,
        prepared: PreparedPinKey,
    ): PinEnvelope {
        var wrapped: ByteArray? = null
        try {
            if (masterKey.size != KeyringCrypto.MASTER_KEY_BYTES) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.INVALID_ARGUMENT,
                )
            }
            val nonce = random.bytes(NONCE_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(
                    Cipher.ENCRYPT_MODE,
                    SecretKeySpec(prepared.kek, "AES"),
                    GCMParameterSpec(TAG_BITS, nonce),
                )
                updateAAD(PinEnvelopeAad.create(keyId, prepared.kdf))
            }
            wrapped = cipher.doFinal(masterKey)
            if (wrapped.size != KeyringCrypto.MASTER_KEY_BYTES + TAG_BYTES) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.INTERNAL_ERROR,
                )
            }
            return PinEnvelope(
                kdf = prepared.kdf,
                nonce = nonce,
                ciphertext = wrapped.copyOfRange(
                    0,
                    KeyringCrypto.MASTER_KEY_BYTES,
                ),
                tag = wrapped.copyOfRange(
                    KeyringCrypto.MASTER_KEY_BYTES,
                    wrapped.size,
                ),
            )
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Throwable) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.INTERNAL_ERROR,
                error,
            )
        } finally {
            wrapped?.fill(0)
            prepared.clear()
        }
    }

    fun unwrap(
        keyId: String,
        envelope: PinEnvelope,
        pin: ByteArray,
    ): ByteArray {
        var kek: ByteArray? = null
        val wrapped = ByteArray(KeyringCrypto.MASTER_KEY_BYTES + TAG_BYTES)
        try {
            validate(envelope)
            kek = keyDeriver.derive(pin, envelope.kdf.salt)
            envelope.ciphertext.copyInto(wrapped)
            envelope.tag.copyInto(wrapped, KeyringCrypto.MASTER_KEY_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(
                    Cipher.DECRYPT_MODE,
                    SecretKeySpec(kek, "AES"),
                    GCMParameterSpec(TAG_BITS, envelope.nonce),
                )
                updateAAD(PinEnvelopeAad.create(keyId, envelope.kdf))
            }
            return cipher.doFinal(wrapped)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: AEADBadTagException) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.PIN_INCORRECT,
                error,
            )
        } catch (error: Throwable) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.INTERNAL_ERROR,
                error,
            )
        } finally {
            kek?.fill(0)
            wrapped.fill(0)
            pin.fill(0)
        }
    }

    private fun validate(envelope: PinEnvelope) {
        if (envelope.kdf.memoryKiB != PinKeyDeriver.MEMORY_KIB ||
            envelope.kdf.iterations != PinKeyDeriver.ITERATIONS ||
            envelope.kdf.parallelism != PinKeyDeriver.PARALLELISM ||
            envelope.kdf.salt.size != PinKeyDeriver.SALT_BYTES ||
            envelope.nonce.size != NONCE_BYTES ||
            envelope.ciphertext.size != KeyringCrypto.MASTER_KEY_BYTES ||
            envelope.tag.size != TAG_BYTES
        ) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.ENVELOPE_CORRUPT,
            )
        }
    }

    companion object {
        private const val NONCE_BYTES = 12
        private const val TAG_BYTES = 16
        private const val TAG_BITS = TAG_BYTES * 8
    }
}
