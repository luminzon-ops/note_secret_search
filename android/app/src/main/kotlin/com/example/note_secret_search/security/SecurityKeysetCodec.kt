package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import org.json.JSONArray
import org.json.JSONObject

object SecurityEnvelopeAad {
    fun create(keyId: String, envelope: SecurityEnvelope): ByteArray {
        val value = buildString {
            append("note-secret-search/key-envelope/v2\n")
            append("keyId=").append(keyId).append('\n')
            append("kind=").append(envelope.kind.serializedName).append('\n')
            append("keyAlias=").append(envelope.keyAlias).append('\n')
            append("algorithm=").append(SecurityKeysetCodec.ALGORITHM).append('\n')
            append("securityLevel=").append(envelope.securityLevel.channelValue)
        }
        return value.toByteArray(StandardCharsets.UTF_8)
    }
}

@OptIn(ExperimentalEncodingApi::class)
object SecurityKeysetCodec {
    const val ALGORITHM = "AES-256-GCM"
    const val PIN_KDF_ALGORITHM = "Argon2id"
    private const val LEGACY_VERSION = 2
    private const val CURRENT_VERSION = 3
    private const val PIN_PURPOSE = "pin"
    private const val PIN_MEMORY_KIB = 65_536
    private const val PIN_ITERATIONS = 3
    private const val PIN_PARALLELISM = 1
    private const val PIN_SALT_BYTES = 16
    private const val PIN_OUTPUT_BYTES = 32
    private const val NONCE_BYTES = 12
    private const val CIPHERTEXT_BYTES = 32
    private const val TAG_BYTES = 16
    private const val MAX_KEYSET_BYTES = 64 * 1024

    fun encode(keyset: SecurityKeyset): ByteArray {
        validateKeyset(keyset)
        val envelopes = JSONArray()
        keyset.envelopes.forEach { envelope ->
            envelopes.put(
                JSONObject()
                    .put("kind", envelope.kind.serializedName)
                    .put("keyAlias", envelope.keyAlias)
                    .put("algorithm", ALGORITHM)
                    .put("nonce", encodeBase64(envelope.nonce))
                    .put("ciphertext", encodeBase64(envelope.ciphertext))
                    .put("tag", encodeBase64(envelope.tag))
                    .put("securityLevel", envelope.securityLevel.channelValue),
            )
        }
        val root = JSONObject()
            .put("version", CURRENT_VERSION)
            .put("keyId", keyset.keyId)
            .put("envelopes", envelopes)
        keyset.pinEnvelope?.let {
            root.put("pinEnvelope", encodePinEnvelope(it))
        }
        return root
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
    }

    fun decode(value: ByteArray): SecurityKeyset {
        return decodeInternal(value, recoverCorruptPin = false)
    }

    fun decodeRecoverable(value: ByteArray): SecurityKeyset {
        return decodeInternal(value, recoverCorruptPin = true)
    }

    private fun decodeInternal(
        value: ByteArray,
        recoverCorruptPin: Boolean,
    ): SecurityKeyset {
        if (value.isEmpty() || value.size > MAX_KEYSET_BYTES) {
            corrupt()
        }
        return try {
            val root = JSONObject(value.toString(StandardCharsets.UTF_8))
            val version = root.getInt("version")
            val rootKeys = mutableSetOf("version", "keyId", "envelopes")
            when (version) {
                LEGACY_VERSION -> Unit
                CURRENT_VERSION -> {
                    if (root.has("pinEnvelope")) {
                        rootKeys += "pinEnvelope"
                    }
                }
                else -> corrupt()
            }
            requireExactKeys(root, rootKeys)
            val keyId = root.getString("keyId")
            val array = root.getJSONArray("envelopes")
            val envelopes = buildList {
                repeat(array.length()) { index ->
                    add(decodeEnvelope(array.getJSONObject(index)))
                }
            }
            var pinResetRequired = false
            val pinEnvelope = if (root.has("pinEnvelope")) {
                try {
                    decodePinEnvelope(root.getJSONObject("pinEnvelope"))
                } catch (error: Exception) {
                    if (!recoverCorruptPin) {
                        throw if (error is NativeSecurityException) {
                            error
                        } else {
                            NativeSecurityException(
                                NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                                error,
                            )
                        }
                    }
                    pinResetRequired = true
                    null
                }
            } else {
                null
            }
            SecurityKeyset(
                keyId = keyId,
                envelopes = envelopes,
                pinEnvelope = pinEnvelope,
                pinResetRequired = pinResetRequired,
            ).also(::validateKeyset)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT, error)
        }
    }

    private fun decodeEnvelope(value: JSONObject): SecurityEnvelope {
        requireExactKeys(
            value,
            setOf(
                "kind",
                "keyAlias",
                "algorithm",
                "nonce",
                "ciphertext",
                "tag",
                "securityLevel",
            ),
        )
        if (value.getString("algorithm") != ALGORITHM) {
            corrupt()
        }
        return SecurityEnvelope(
            kind = EnvelopeKind.fromSerializedName(value.getString("kind")),
            keyAlias = value.getString("keyAlias"),
            nonce = decodeBase64(value.getString("nonce")),
            ciphertext = decodeBase64(value.getString("ciphertext")),
            tag = decodeBase64(value.getString("tag")),
            securityLevel = KeySecurityLevel.fromChannelValue(
                value.getString("securityLevel"),
            ),
        )
    }

    private fun encodePinEnvelope(envelope: PinEnvelope): JSONObject {
        return JSONObject()
            .put("purpose", PIN_PURPOSE)
            .put("algorithm", ALGORITHM)
            .put(
                "kdf",
                JSONObject()
                    .put("algorithm", PIN_KDF_ALGORITHM)
                    .put("memoryKiB", envelope.kdf.memoryKiB)
                    .put("iterations", envelope.kdf.iterations)
                    .put("parallelism", envelope.kdf.parallelism)
                    .put("salt", encodeBase64(envelope.kdf.salt))
                    .put("outputBytes", PIN_OUTPUT_BYTES),
            )
            .put("nonce", encodeBase64(envelope.nonce))
            .put("ciphertext", encodeBase64(envelope.ciphertext))
            .put("tag", encodeBase64(envelope.tag))
    }

    private fun decodePinEnvelope(value: JSONObject): PinEnvelope {
        requireExactKeys(
            value,
            setOf(
                "purpose",
                "algorithm",
                "kdf",
                "nonce",
                "ciphertext",
                "tag",
            ),
        )
        if (value.getString("purpose") != PIN_PURPOSE ||
            value.getString("algorithm") != ALGORITHM
        ) {
            corrupt()
        }
        val kdf = value.getJSONObject("kdf")
        requireExactKeys(
            kdf,
            setOf(
                "algorithm",
                "memoryKiB",
                "iterations",
                "parallelism",
                "salt",
                "outputBytes",
            ),
        )
        if (kdf.getString("algorithm") != PIN_KDF_ALGORITHM ||
            kdf.getInt("outputBytes") != PIN_OUTPUT_BYTES
        ) {
            corrupt()
        }
        return PinEnvelope(
            kdf = PinKdfParameters(
                memoryKiB = kdf.getInt("memoryKiB"),
                iterations = kdf.getInt("iterations"),
                parallelism = kdf.getInt("parallelism"),
                salt = decodeBase64(kdf.getString("salt")),
            ),
            nonce = decodeBase64(value.getString("nonce")),
            ciphertext = decodeBase64(value.getString("ciphertext")),
            tag = decodeBase64(value.getString("tag")),
        )
    }

    private fun validateKeyset(keyset: SecurityKeyset) {
        val keyId = try {
            UUID.fromString(keyset.keyId).toString()
        } catch (error: IllegalArgumentException) {
            throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT, error)
        }
        if (keyId != keyset.keyId || keyset.envelopes.isEmpty()) {
            corrupt()
        }
        val kinds = mutableSetOf<EnvelopeKind>()
        keyset.envelopes.forEach { envelope ->
            if (!kinds.add(envelope.kind)) {
                corrupt()
            }
            val expectedAlias = "note_secret_search.keyring.v2.$keyId." +
                envelope.kind.serializedName
            if (envelope.keyAlias != expectedAlias ||
                envelope.nonce.size != NONCE_BYTES ||
                envelope.ciphertext.size != CIPHERTEXT_BYTES ||
                envelope.tag.size != TAG_BYTES
            ) {
                corrupt()
            }
        }
        keyset.pinEnvelope?.let(::validatePinEnvelope)
    }

    private fun validatePinEnvelope(envelope: PinEnvelope) {
        if (envelope.kdf.memoryKiB != PIN_MEMORY_KIB ||
            envelope.kdf.iterations != PIN_ITERATIONS ||
            envelope.kdf.parallelism != PIN_PARALLELISM ||
            envelope.kdf.salt.size != PIN_SALT_BYTES ||
            envelope.nonce.size != NONCE_BYTES ||
            envelope.ciphertext.size != CIPHERTEXT_BYTES ||
            envelope.tag.size != TAG_BYTES
        ) {
            corrupt()
        }
    }

    private fun requireExactKeys(value: JSONObject, expected: Set<String>) {
        val actual = mutableSetOf<String>()
        value.keys().forEachRemaining(actual::add)
        if (actual != expected) {
            corrupt()
        }
    }

    private fun encodeBase64(value: ByteArray): String {
        return Base64.encode(value)
    }

    private fun decodeBase64(value: String): ByteArray {
        return try {
            Base64.decode(value)
        } catch (error: IllegalArgumentException) {
            throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT, error)
        }
    }

    private fun corrupt(): Nothing {
        throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT)
    }
}
