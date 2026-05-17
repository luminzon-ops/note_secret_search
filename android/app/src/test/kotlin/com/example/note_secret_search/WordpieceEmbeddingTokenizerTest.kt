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
}
