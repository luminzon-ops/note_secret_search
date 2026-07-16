package com.example.note_secret_search.security

import java.io.FileNotFoundException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
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
        val result = readRecoverableAtomicFile(
            stateFilesExist = { false },
            readFully = { throw FileNotFoundException("missing") },
        )

        assertNull(result)
    }

    @Test
    fun `read fails closed when recovery material exists but cannot be opened`() {
        val error = assertThrows(NativeSecurityException::class.java) {
            readRecoverableAtomicFile(
                stateFilesExist = { true },
                readFully = { throw FileNotFoundException("recovery failed") },
            )
        }

        assertTrue(error.code == NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE)
    }

    @Test
    fun `read fails closed when recovery material disappears during the read`() {
        var recoveryMaterialExists = true

        val error = assertThrows(NativeSecurityException::class.java) {
            readRecoverableAtomicFile(
                stateFilesExist = { recoveryMaterialExists },
                readFully = {
                    recoveryMaterialExists = false
                    throw FileNotFoundException("raced with cleanup")
                },
            )
        }

        assertTrue(error.code == NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE)
    }
}
