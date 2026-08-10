package com.example.note_secret_search.security

import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PinEnvelopeCryptoTest {
    @Test
    fun `wraps and unwraps the master key with the versioned PIN context`() {
        val random = FixedRandomSource().apply {
            enqueue(ByteArray(16) { (it + 2).toByte() })
            enqueue(ByteArray(12) { (it + 30).toByte() })
        }
        val crypto = PinEnvelopeCrypto(
            keyDeriver = PinKeyDeriver(EnvelopeTestPinKdfEngine()),
            random = random,
        )
        val keyId = "123e4567-e89b-12d3-a456-426614174000"
        val expectedMasterKey = ByteArray(32) { (it + 70).toByte() }
        val masterKey = expectedMasterKey.clone()
        val configurePin = "2468".toByteArray()

        val prepared = crypto.prepare(configurePin)
        val envelope = crypto.wrap(keyId, masterKey, prepared)

        assertEquals(65_536, envelope.kdf.memoryKiB)
        assertEquals(3, envelope.kdf.iterations)
        assertEquals(1, envelope.kdf.parallelism)
        assertEquals(16, envelope.kdf.salt.size)
        assertEquals(12, envelope.nonce.size)
        assertEquals(32, envelope.ciphertext.size)
        assertEquals(16, envelope.tag.size)
        assertArrayEquals(expectedMasterKey, masterKey)
        assertTrue(configurePin.all { it == 0.toByte() })
        assertTrue(prepared.kek.all { it == 0.toByte() })

        val unlockPin = "2468".toByteArray()
        val unwrapped = crypto.unwrap(keyId, envelope, unlockPin)

        assertArrayEquals(expectedMasterKey, unwrapped)
        assertTrue(unlockPin.all { it == 0.toByte() })
    }

    @Test
    fun `wrong PIN returns the stable error and clears the attempted PIN`() {
        val random = FixedRandomSource().apply {
            enqueue(ByteArray(16) { (it + 2).toByte() })
            enqueue(ByteArray(12) { (it + 30).toByte() })
        }
        val crypto = PinEnvelopeCrypto(
            keyDeriver = PinKeyDeriver(EnvelopeTestPinKdfEngine()),
            random = random,
        )
        val keyId = "123e4567-e89b-12d3-a456-426614174000"
        val envelope = crypto.wrap(
            keyId = keyId,
            masterKey = ByteArray(32) { (it + 70).toByte() },
            prepared = crypto.prepare("2468".toByteArray()),
        )
        val wrongPin = "1357".toByteArray()

        try {
            crypto.unwrap(keyId, envelope, wrongPin)
            fail("Expected the wrong PIN to be rejected.")
        } catch (error: NativeSecurityException) {
            assertEquals(NativeSecurityErrorCode.PIN_INCORRECT, error.code)
        }

        assertTrue(wrongPin.all { it == 0.toByte() })
    }

    @Test
    fun `tampered PIN envelope returns the stable error and clears the PIN`() {
        val random = FixedRandomSource().apply {
            enqueue(ByteArray(16) { (it + 2).toByte() })
            enqueue(ByteArray(12) { (it + 30).toByte() })
        }
        val crypto = PinEnvelopeCrypto(
            keyDeriver = PinKeyDeriver(EnvelopeTestPinKdfEngine()),
            random = random,
        )
        val keyId = "123e4567-e89b-12d3-a456-426614174000"
        val envelope = crypto.wrap(
            keyId = keyId,
            masterKey = ByteArray(32) { (it + 70).toByte() },
            prepared = crypto.prepare("2468".toByteArray()),
        )
        val tamperedEnvelopes = listOf<PinEnvelope>(
            PinEnvelope(
                kdf = envelope.kdf,
                nonce = envelope.nonce.tamperLastByte(),
                ciphertext = envelope.ciphertext.clone(),
                tag = envelope.tag.clone(),
            ),
            PinEnvelope(
                kdf = envelope.kdf,
                nonce = envelope.nonce.clone(),
                ciphertext = envelope.ciphertext.tamperLastByte(),
                tag = envelope.tag.clone(),
            ),
            PinEnvelope(
                kdf = envelope.kdf,
                nonce = envelope.nonce.clone(),
                ciphertext = envelope.ciphertext.clone(),
                tag = envelope.tag.tamperLastByte(),
            ),
        )

        tamperedEnvelopes.forEach { tampered ->
            val pin = "2468".toByteArray()
            try {
                crypto.unwrap(keyId, tampered, pin)
                fail("Expected the tampered PIN envelope to be rejected.")
            } catch (error: NativeSecurityException) {
                assertEquals(NativeSecurityErrorCode.PIN_INCORRECT, error.code)
            }
            assertTrue(pin.all { it == 0.toByte() })
        }
    }
}

private fun ByteArray.tamperLastByte(): ByteArray {
    return clone().apply {
        this[lastIndex] = (this[lastIndex].toInt() xor 0x01).toByte()
    }
}

private class EnvelopeTestPinKdfEngine : PinKdfEngine {
    override fun derive(
        password: ByteArray,
        salt: ByteArray,
        iterations: Int,
        memoryKiB: Int,
        parallelism: Int,
        outputBytes: Int,
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(password)
        digest.update(salt)
        return digest.digest().copyOf(outputBytes)
    }
}
