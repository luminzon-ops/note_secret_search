package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Test

class EmbeddingRuntimeExceptionTest {
    @Test
    fun `wrap exposes stable runtime metadata without raw cause text`() {
        val error = EmbeddingRuntimeException.wrap(
            error = IllegalStateException(
                "MODEL_PATH_SENTINEL=/private/model.onnx TEXT_SENTINEL=secret",
            ),
            code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
            stage = EmbeddingRuntimeStage.SESSION_LOAD,
            modelId = "bge_small_zh_v1_5",
        )

        assertEquals("ORT_FAILURE", error.code.wireName)
        assertEquals("session_load", error.stage.wireName)
        assertEquals("bge_small_zh_v1_5", error.modelId)
        assertEquals("ORT_FAILURE", error.message)
        assertFalse(error.message.orEmpty().contains("MODEL_PATH_SENTINEL"))
        assertFalse(error.message.orEmpty().contains("TEXT_SENTINEL"))
    }

    @Test
    fun `wrap preserves typed error and fills missing model id`() {
        val typed = EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.INVALID_OUTPUT,
            stage = EmbeddingRuntimeStage.OUTPUT,
            modelId = null,
        )

        val error = EmbeddingRuntimeException.wrap(
            error = typed,
            code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
            stage = EmbeddingRuntimeStage.INFERENCE,
            modelId = "model-a",
        )

        assertEquals(EmbeddingRuntimeErrorCode.INVALID_OUTPUT, error.code)
        assertEquals(EmbeddingRuntimeStage.OUTPUT, error.stage)
        assertEquals("model-a", error.modelId)
        assertEquals("INVALID_OUTPUT", error.message)
        assertSame(typed.cause, error.cause)
    }
}
