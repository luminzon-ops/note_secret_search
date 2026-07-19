package com.example.note_secret_search.security

import java.nio.charset.StandardCharsets
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object KeyDerivationLabels {
    val DATABASE: ByteArray =
        "note-secret-search/sqlcipher/v1".toByteArray(StandardCharsets.UTF_8)
    val FIELD: ByteArray =
        "note-secret-search/field/v1".toByteArray(StandardCharsets.UTF_8)
    val SEARCH_INDEX_FINGERPRINT: ByteArray =
        "note-secret-search/search-index-fingerprint/v1"
            .toByteArray(StandardCharsets.UTF_8)
}

object HkdfSha256 {
    private const val HASH_LENGTH = 32

    fun derive(
        inputKeyMaterial: ByteArray,
        info: ByteArray,
        outputLength: Int = HASH_LENGTH,
    ): ByteArray {
        require(inputKeyMaterial.isNotEmpty())
        require(outputLength in 1..(255 * HASH_LENGTH))

        val salt = ByteArray(HASH_LENGTH)
        val pseudoRandomKey = hmac(salt, inputKeyMaterial)
        salt.fill(0)

        val output = ByteArray(outputLength)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < outputLength) {
            val input = previous + info + byteArrayOf(counter.toByte())
            previous.fill(0)
            previous = hmac(pseudoRandomKey, input)
            input.fill(0)
            val count = minOf(previous.size, outputLength - offset)
            previous.copyInto(output, offset, 0, count)
            offset += count
            counter += 1
        }
        previous.fill(0)
        pseudoRandomKey.fill(0)
        return output
    }

    private fun hmac(key: ByteArray, input: ByteArray): ByteArray {
        return Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(input)
        }
    }
}
