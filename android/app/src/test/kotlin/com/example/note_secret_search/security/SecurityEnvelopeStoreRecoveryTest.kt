package com.example.note_secret_search.security

import java.io.FileNotFoundException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityEnvelopeStoreRecoveryTest {
    @Test
    fun `read attempts atomic recovery before treating keyset as absent`() {
        var attempted = false
        val recovered = byteArrayOf(1, 2, 3)

        val result = readRecoverableAtomicFile {
            attempted = true
            recovered
        }

        assertTrue(attempted)
        assertArrayEquals(recovered, result)
    }

    @Test
    fun `read treats a missing base and backup as unprovisioned`() {
        val result = readRecoverableAtomicFile {
            throw FileNotFoundException("missing")
        }

        assertNull(result)
    }
}
