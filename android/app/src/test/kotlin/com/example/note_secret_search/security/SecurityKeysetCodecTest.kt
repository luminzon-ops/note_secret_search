package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityKeysetCodecTest {
    private val envelope = SecurityEnvelope(
        kind = EnvelopeKind.COMBINED,
        keyAlias = "note_secret_search.keyring.v2.123e4567-e89b-12d3-a456-426614174000.combined",
        nonce = ByteArray(12) { it.toByte() },
        ciphertext = ByteArray(32) { (it + 10).toByte() },
        tag = ByteArray(16) { (it + 42).toByte() },
        securityLevel = KeySecurityLevel.TEE,
    )
    private val keyset = SecurityKeyset(
        keyId = "123e4567-e89b-12d3-a456-426614174000",
        envelopes = listOf(envelope),
    )

    @Test
    fun `round trips a versioned AES GCM keyset without plaintext key fields`() {
        val encoded = SecurityKeysetCodec.encode(keyset)
        val json = encoded.toString(StandardCharsets.UTF_8)

        assertEquals(keyset, SecurityKeysetCodec.decode(encoded))
        assertTrue(json.contains("\"version\":2"))
        assertTrue(json.contains("\"algorithm\":\"AES-256-GCM\""))
        assertTrue(json.contains("\"ciphertext\":"))
        assertTrue(json.contains("\"tag\":"))
        assertFalse(json.contains("databaseKey"))
        assertFalse(json.contains("fieldKey"))
        assertFalse(json.contains("masterKey"))
    }

    @Test
    fun `binds envelope metadata into deterministic authenticated data`() {
        val aad = SecurityEnvelopeAad.create(keyset.keyId, envelope)

        assertArrayEquals(
            (
                "note-secret-search/key-envelope/v2\n" +
                    "keyId=123e4567-e89b-12d3-a456-426614174000\n" +
                    "kind=combined\n" +
                    "keyAlias=note_secret_search.keyring.v2." +
                    "123e4567-e89b-12d3-a456-426614174000.combined\n" +
                    "algorithm=AES-256-GCM\n" +
                    "securityLevel=tee"
                ).toByteArray(StandardCharsets.UTF_8),
            aad,
        )
    }

    @Test
    fun `round trips unknown security level without making a hardware claim`() {
        val unknown = keyset.copy(
            envelopes = listOf(
                envelope.copy(securityLevel = KeySecurityLevel.UNKNOWN),
            ),
        )

        val decoded = SecurityKeysetCodec.decode(SecurityKeysetCodec.encode(unknown))

        assertEquals(KeySecurityLevel.UNKNOWN, decoded.envelopes.single().securityLevel)
    }

    @Test(expected = NativeSecurityException::class)
    fun `rejects unknown envelope algorithms`() {
        val malformed = SecurityKeysetCodec.encode(keyset)
            .toString(StandardCharsets.UTF_8)
            .replace("AES-256-GCM", "AES-128-CBC")
            .toByteArray(StandardCharsets.UTF_8)

        SecurityKeysetCodec.decode(malformed)
    }

    @Test(expected = NativeSecurityException::class)
    fun `rejects malformed nonce lengths`() {
        val malformed = SecurityKeysetCodec.encode(keyset.copy(
            envelopes = listOf(envelope.copy(nonce = ByteArray(11))),
        ))

        SecurityKeysetCodec.decode(malformed)
    }

    @Test(expected = NativeSecurityException::class)
    fun `rejects malformed ciphertext lengths`() {
        SecurityKeysetCodec.encode(keyset.copy(
            envelopes = listOf(envelope.copy(ciphertext = ByteArray(31))),
        ))
    }

    @Test(expected = NativeSecurityException::class)
    fun `rejects malformed authentication tag lengths`() {
        SecurityKeysetCodec.encode(keyset.copy(
            envelopes = listOf(envelope.copy(tag = ByteArray(15))),
        ))
    }

    @Test(expected = NativeSecurityException::class)
    fun `rejects keysets with a missing authentication tag field`() {
        val malformed = SecurityKeysetCodec.encode(keyset)
            .toString(StandardCharsets.UTF_8)
            .replace(Regex(",\"tag\":\"[^\"]+\""), "")
            .toByteArray(StandardCharsets.UTF_8)

        SecurityKeysetCodec.decode(malformed)
    }
}
