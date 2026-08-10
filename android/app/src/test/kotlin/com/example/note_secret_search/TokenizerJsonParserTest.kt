package com.example.note_secret_search

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenizerJsonParserTest {
    @Test
    fun `parses catalog BERT WordPiece metadata`() {
        val definition = TokenizerJsonParser.parse(
            rawJson = bgeTokenizerJson(),
            expectedLowercase = false,
        )

        assertEquals("1.0", definition.version)
        assertTrue(definition.normalizer.cleanText)
        assertTrue(definition.normalizer.handleChineseChars)
        assertNull(definition.normalizer.stripAccents)
        assertFalse(definition.normalizer.lowercase)
        assertEquals("[UNK]", definition.unknownToken)
        assertEquals("##", definition.continuingSubwordPrefix)
        assertEquals(100, definition.maxInputCharsPerWord)
        assertEquals(21128, definition.vocab.size)
        assertEquals(0, definition.padTokenId)
        assertEquals(100, definition.unknownTokenId)
        assertEquals(101, definition.clsTokenId)
        assertEquals(102, definition.sepTokenId)
        assertEquals(3, definition.singleTemplate.size)
    }

    @Test
    fun `rejects catalog lowercase that disagrees with tokenizer normalizer`() {
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            TokenizerJsonParser.parse(
                rawJson = bgeTokenizerJson(),
                expectedLowercase = true,
            )
        }
    }
}

internal fun bgeTokenizerJson(): String {
    val projectDir = File(System.getProperty("user.dir"))
    return projectDir
        .resolve("../../assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json")
        .canonicalFile
        .readText()
}
