package com.example.note_secret_search.security

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PinKeyDeriverInstrumentationTest {
    @Test
    fun derivesTheFixedArgon2idV13VectorAndClearsThePin() {
        val pin = "2468".toByteArray()
        val salt = ByteArray(16) { index -> index.toByte() }

        val key = PinKeyDeriver(Argon2KtPinKdfEngine()).derive(pin, salt)

        assertArrayEquals(
            (
                "0d7ca8c93f53044ae3266257c20eb323" +
                    "6e51d9d13970c3a669de63f1f4883aff"
            ).hexBytes(),
            key,
        )
        assertTrue(pin.all { value -> value == 0.toByte() })
    }
}

private fun String.hexBytes(): ByteArray {
    require(length % 2 == 0)
    return chunked(2)
        .map { pair -> pair.toInt(radix = 16).toByte() }
        .toByteArray()
}
