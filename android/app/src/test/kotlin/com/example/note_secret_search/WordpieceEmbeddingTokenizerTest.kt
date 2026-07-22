package com.example.note_secret_search

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class WordpieceEmbeddingTokenizerTest {
    private val tokenizer = WordpieceEmbeddingTokenizer(
        vocab = mapOf(
            "[PAD]" to 0,
            "[UNK]" to 100,
            "[CLS]" to 101,
            "[SEP]" to 102,
            "hello" to 2001,
            "world" to 2002,
            "##s" to 2003,
        ),
        lowercase = true,
        maxSequenceLength = 8,
    )

    @Test
    fun `encode builds input ids and attention mask with special tokens and padding`() {
        val encoded = tokenizer.encode("Hello worlds")

        assertArrayEquals(longArrayOf(101, 2001, 2002, 2003, 102, 0, 0, 0), encoded.inputIds)
        assertArrayEquals(longArrayOf(1, 1, 1, 1, 1, 0, 0, 0), encoded.attentionMask)
        assertArrayEquals(longArrayOf(0, 0, 0, 0, 0, 0, 0, 0), encoded.tokenTypeIds)
    }

    @Test
    fun `encode falls back to unknown token when wordpiece split fails`() {
        val encoded = tokenizer.encode("mystery")

        assertArrayEquals(longArrayOf(101, 100, 102, 0, 0, 0, 0, 0), encoded.inputIds)
        assertArrayEquals(longArrayOf(1, 1, 1, 0, 0, 0, 0, 0), encoded.attentionMask)
    }

    @Test
    fun `encode rejects an overlong word even when the full token exists in vocab`() {
        val overlongWord = "a".repeat(101)
        val overlongTokenizer = WordpieceEmbeddingTokenizer(
            definition = TokenizerDefinition.legacy(
                vocab = mapOf(
                    "[PAD]" to 0,
                    "[UNK]" to 100,
                    "[CLS]" to 101,
                    "[SEP]" to 102,
                    overlongWord to 2001,
                ),
                lowercase = false,
            ),
            maxSequenceLength = 8,
        )

        assertArrayEquals(
            longArrayOf(101, 100, 102),
            overlongTokenizer.encode(overlongWord, padToLength = null).inputIds,
        )
    }

    @Test
    fun `catalog tokenizer matches Chinese and mixed punctuation golden corpus`() {
        val catalogTokenizer = catalogTokenizer()

        assertArrayEquals(
            longArrayOf(101, 704, 3152, 3017, 5164, 102),
            catalogTokenizer.encode("中文搜索", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 100, 117, 686, 4518, 8013, 102),
            catalogTokenizer.encode("Hello, 世界！", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 2166, 4772, 8038, 100, 137, 10239, 8220, 8129, 8642, 102),
            catalogTokenizer.encode("密码：P@ssw0rd", padToLength = null).inputIds,
        )
    }

    @Test
    fun `catalog tokenizer matches lowercase accent whitespace and control behavior`() {
        val catalogTokenizer = catalogTokenizer()

        assertArrayEquals(
            longArrayOf(101, 100, 8701, 102),
            catalogTokenizer.encode("HELLO hello", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 100, 100, 102),
            catalogTokenizer.encode("Café cafe\u0301", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 704, 3152, 3017, 5164, 102),
            catalogTokenizer.encode("  中\t文\r\n搜索  ", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 704, 3152, 3017, 5164, 102),
            catalogTokenizer.encode("\u0000中\u0007文\u200B搜索", padToLength = null).inputIds,
        )
    }

    @Test
    fun `catalog tokenizer handles supplementary scalars special tokens and long unknown words`() {
        val catalogTokenizer = catalogTokenizer()

        assertArrayEquals(
            longArrayOf(101, 100, 704, 3152, 102),
            catalogTokenizer.encode("\uD840\uDC00中文", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 101, 704, 3152, 102, 102),
            catalogTokenizer.encode("[CLS] 中文 [SEP]", padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 100, 102),
            catalogTokenizer.encode("a".repeat(101), padToLength = null).inputIds,
        )
        assertArrayEquals(
            longArrayOf(101, 8701, 118, 8572, 102),
            catalogTokenizer.encode("hello-world", padToLength = null).inputIds,
        )
    }

    private fun catalogTokenizer(): WordpieceEmbeddingTokenizer {
        return WordpieceEmbeddingTokenizer(
            definition = TokenizerJsonParser.parse(
                rawJson = bgeTokenizerJson(),
                expectedLowercase = false,
            ),
            maxSequenceLength = 256,
        )
    }
}
