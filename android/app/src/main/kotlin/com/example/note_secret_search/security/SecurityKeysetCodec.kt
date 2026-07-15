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
    private const val VERSION = 2
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
        return JSONObject()
            .put("version", VERSION)
            .put("keyId", keyset.keyId)
            .put("envelopes", envelopes)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
    }

    fun decode(value: ByteArray): SecurityKeyset {
        if (value.isEmpty() || value.size > MAX_KEYSET_BYTES) {
            corrupt()
        }
        return try {
            val root = JSONObject(value.toString(StandardCharsets.UTF_8))
            requireExactKeys(root, setOf("version", "keyId", "envelopes"))
            if (root.getInt("version") != VERSION) {
                corrupt()
            }
            val keyId = root.getString("keyId")
            val array = root.getJSONArray("envelopes")
            val envelopes = buildList {
                repeat(array.length()) { index ->
                    add(decodeEnvelope(array.getJSONObject(index)))
                }
            }
            SecurityKeyset(keyId, envelopes).also(::validateKeyset)
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
