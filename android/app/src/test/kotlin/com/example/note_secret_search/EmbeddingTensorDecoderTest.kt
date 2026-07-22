package com.example.note_secret_search

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class EmbeddingTensorDecoderTest {
    @Test
    fun `decodes rank three float output into copied token vectors`() {
        val source = arrayOf(
            arrayOf(
                floatArrayOf(1f, 2f),
                floatArrayOf(3f, 4f),
            ),
        )

        val decoded = EmbeddingTensorDecoder.decode(
            type = ModelTensorType.FLOAT,
            shape = longArrayOf(1, 2, 2),
            value = source,
        )
        source[0][0][0] = 99f

        assertEquals(EmbeddingTensorKind.TOKEN, decoded.kind)
        assertArrayEquals(floatArrayOf(1f, 2f), decoded.tokenVectors[0], 0f)
        assertArrayEquals(floatArrayOf(3f, 4f), decoded.tokenVectors[1], 0f)
    }

    @Test
    fun `decodes rank two float output into copied sentence vector`() {
        val source = arrayOf(floatArrayOf(0.25f, 0.75f))

        val decoded = EmbeddingTensorDecoder.decode(
            type = ModelTensorType.FLOAT,
            shape = longArrayOf(1, 2),
            value = source,
        )
        source[0][0] = 9f

        assertEquals(EmbeddingTensorKind.SENTENCE, decoded.kind)
        assertArrayEquals(floatArrayOf(0.25f, 0.75f), decoded.sentenceVector, 0f)
    }

    @Test
    fun `rejects non float output unsupported rank and shape mismatch`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingTensorDecoder.decode(
                type = ModelTensorType.INT64,
                shape = longArrayOf(1, 2),
                value = arrayOf(floatArrayOf(1f, 2f)),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingTensorDecoder.decode(
                type = ModelTensorType.FLOAT,
                shape = longArrayOf(2),
                value = floatArrayOf(1f, 2f),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingTensorDecoder.decode(
                type = ModelTensorType.FLOAT,
                shape = longArrayOf(1, 3, 2),
                value = arrayOf(
                    arrayOf(
                        floatArrayOf(1f, 2f),
                        floatArrayOf(3f, 4f),
                    ),
                ),
            )
        }
    }

    @Test
    fun `rejects ragged and non finite output carriers`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingTensorDecoder.decode(
                type = ModelTensorType.FLOAT,
                shape = longArrayOf(1, 2, 2),
                value = arrayOf(
                    arrayOf(
                        floatArrayOf(1f, 2f),
                        floatArrayOf(3f),
                    ),
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingTensorDecoder.decode(
                type = ModelTensorType.FLOAT,
                shape = longArrayOf(1, 2),
                value = arrayOf(floatArrayOf(Float.POSITIVE_INFINITY, 2f)),
            )
        }
    }
}
