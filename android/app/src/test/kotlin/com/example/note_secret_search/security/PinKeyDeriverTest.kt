package com.example.note_secret_search.security

import com.lambdapioneer.argon2kt.Argon2KtResult
import java.nio.ByteBuffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PinKeyDeriverTest {
    @Test
    fun `derives a 32 byte key with the fixed Argon2id policy and clears the PIN`() {
        val engine = RecordingPinKdfEngine()
        val deriver = PinKeyDeriver(engine)
        val pin = "2468".toByteArray()
        val salt = ByteArray(16) { (it + 1).toByte() }

        val key = deriver.derive(pin, salt)

        assertEquals(3, engine.iterations)
        assertEquals(65_536, engine.memoryKiB)
        assertEquals(1, engine.parallelism)
        assertEquals(32, engine.outputBytes)
        assertArrayEquals(salt, engine.salt)
        assertArrayEquals("2468".toByteArray(), engine.password)
        assertArrayEquals(ByteArray(32) { 0x5a }, key)
        assertTrue(pin.all { it == 0.toByte() })
    }

    @Test
    fun `copies the raw hash and clears Argon2 result buffers`() {
        val raw = directBuffer(ByteArray(32) { (it + 1).toByte() })
        val encoded = directBuffer("encoded-output".toByteArray())
        val result = Argon2KtResult(raw, encoded)

        val copied = copyRawHashAndZeroize(result)

        assertArrayEquals(ByteArray(32) { (it + 1).toByte() }, copied)
        assertTrue(raw.isZeroed())
        assertTrue(encoded.isZeroed())
    }
}

private fun directBuffer(value: ByteArray): ByteBuffer {
    return ByteBuffer.allocateDirect(value.size).apply {
        put(value)
        flip()
    }
}

private fun ByteBuffer.isZeroed(): Boolean {
    return (0 until capacity()).all { index -> get(index) == 0.toByte() }
}

private class RecordingPinKdfEngine : PinKdfEngine {
    var password: ByteArray? = null
    var salt: ByteArray? = null
    var iterations = 0
    var memoryKiB = 0
    var parallelism = 0
    var outputBytes = 0

    override fun derive(
        password: ByteArray,
        salt: ByteArray,
        iterations: Int,
        memoryKiB: Int,
        parallelism: Int,
        outputBytes: Int,
    ): ByteArray {
        this.password = password.clone()
        this.salt = salt.clone()
        this.iterations = iterations
        this.memoryKiB = memoryKiB
        this.parallelism = parallelism
        this.outputBytes = outputBytes
        return ByteArray(outputBytes) { 0x5a }
    }
}
