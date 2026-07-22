package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import kotlin.math.abs

class EmbeddingVectorPostProcessorTest {
    @Test
    fun `cls pooling returns first token vector`() {
        val pooled = EmbeddingVectorPostProcessor.pool(
            tokenVectors = arrayOf(
                floatArrayOf(1f, 2f),
                floatArrayOf(10f, 20f),
            ),
            attentionMask = longArrayOf(1, 1),
            pooling = "cls",
        )

        assertEquals(listOf(1.0, 2.0), pooled)
    }

    @Test
    fun `mean pooling ignores padded positions`() {
        val pooled = EmbeddingVectorPostProcessor.pool(
            tokenVectors = arrayOf(
                floatArrayOf(1f, 3f),
                floatArrayOf(5f, 7f),
                floatArrayOf(100f, 100f),
            ),
            attentionMask = longArrayOf(1, 1, 0),
            pooling = "mean",
        )

        assertEquals(3.0, pooled[0], 0.0001)
        assertEquals(5.0, pooled[1], 0.0001)
    }

    @Test
    fun `l2 normalization returns unit vector`() {
        val normalized = EmbeddingVectorPostProcessor.normalize(
            values = listOf(3.0, 4.0),
            normalization = "l2",
        )

        assertEquals(0.6, normalized[0], 0.0001)
        assertEquals(0.8, normalized[1], 0.0001)
        assertEquals(1.0, normalized[0] * normalized[0] + normalized[1] * normalized[1], 0.0001)
        assertEquals(true, abs(normalized[0]) <= 1.0)
    }

    @Test
    fun `pool rejects unsupported pooling instead of silently using cls`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.pool(
                tokenVectors = arrayOf(floatArrayOf(1f, 2f)),
                attentionMask = longArrayOf(1),
                pooling = "mystery",
            )
        }
    }

    @Test
    fun `mean pooling rejects mask and tensor sequence mismatch`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.pool(
                tokenVectors = arrayOf(
                    floatArrayOf(1f, 2f),
                    floatArrayOf(3f, 4f),
                ),
                attentionMask = longArrayOf(1),
                pooling = "mean",
            )
        }
    }

    @Test
    fun `mean pooling rejects ragged token vectors`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.pool(
                tokenVectors = arrayOf(
                    floatArrayOf(1f, 2f),
                    floatArrayOf(3f),
                ),
                attentionMask = longArrayOf(1, 1),
                pooling = "mean",
            )
        }
    }

    @Test
    fun `pool rejects non finite tensor values`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.pool(
                tokenVectors = arrayOf(floatArrayOf(Float.NaN, 2f)),
                attentionMask = longArrayOf(1),
                pooling = "cls",
            )
        }
    }

    @Test
    fun `mean pooling rejects an all zero attention mask`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.pool(
                tokenVectors = arrayOf(floatArrayOf(1f, 2f)),
                attentionMask = longArrayOf(0),
                pooling = "mean",
            )
        }
    }

    @Test
    fun `normalization rejects unsupported mode and zero norm`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.normalize(
                values = listOf(1.0, 2.0),
                normalization = "mystery",
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.normalize(
                values = listOf(0.0, 0.0),
                normalization = "l2",
            )
        }
    }

    @Test
    fun `normalization none still rejects a zero vector`() {
        assertThrows(IllegalArgumentException::class.java) {
            EmbeddingVectorPostProcessor.normalize(
                values = listOf(0.0, -0.0),
                normalization = "none",
            )
        }
    }
}
