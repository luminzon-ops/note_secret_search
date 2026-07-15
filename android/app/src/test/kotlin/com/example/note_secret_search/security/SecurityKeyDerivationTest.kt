package com.example.note_secret_search.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class SecurityKeyDerivationTest {
    @Test
    fun `derives independent database and field keys from fixed labels`() {
        val masterKey = ByteArray(32) { it.toByte() }

        val databaseKey = HkdfSha256.derive(
            inputKeyMaterial = masterKey,
            info = KeyDerivationLabels.DATABASE,
        )
        val fieldKey = HkdfSha256.derive(
            inputKeyMaterial = masterKey,
            info = KeyDerivationLabels.FIELD,
        )

        assertArrayEquals(
            hex("1ca03149418a383c3e76b0d7ae051f0bb41f6ccd25b92c52c50ba1a7eb2732d3"),
            databaseKey,
        )
        assertArrayEquals(
            hex("6120423c80ff3360487f604d97a73796dce6816a33c9ba88ddde1606f02f5261"),
            fieldKey,
        )
        assertFalse(databaseKey.contentEquals(fieldKey))
    }

    private fun hex(value: String): ByteArray {
        return value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
}
