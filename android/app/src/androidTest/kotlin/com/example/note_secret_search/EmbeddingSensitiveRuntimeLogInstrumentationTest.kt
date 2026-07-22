package com.example.note_secret_search

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class EmbeddingSensitiveRuntimeLogInstrumentationTest {
    @Test
    fun realEmbeddingInferenceDoesNotRequireSensitiveLogValues() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val modelPath = InstrumentationRegistry.getArguments()
            .getString(BgeEmbeddingRuntimeInstrumentationTest.BGE_MODEL_PATH_ARGUMENT)
        assertFalse(
            "Pass the pinned BGE model path through instrumentation arguments.",
            modelPath.isNullOrBlank(),
        )
        val model = File(requireNotNull(modelPath))
        assertTrue("Pinned BGE model is missing on the device.", model.isFile)

        val runtime = OnnxEmbeddingRuntime(
            context = context,
            sessionManager = EmbeddingModelSessionManager(),
        )
        try {
            val ready = runtime.ensureModelReady(
                modelId = "embedding-log-smoke",
                modelPath = model.path,
                spec = bgeModelSpec(),
                verifiedChecksum = BgeEmbeddingRuntimeInstrumentationTest.BGE_CHECKSUM,
            )
            val result = runtime.embedText(
                modelId = "embedding-log-smoke",
                modelPath = model.path,
                text = "$TEXT_SENTINEL 中文搜索",
                spec = bgeModelSpec(),
                verifiedChecksum = BgeEmbeddingRuntimeInstrumentationTest.BGE_CHECKSUM,
                requestId = "embedding-sensitive-log-request",
            )

            assertEquals("ready", ready["status"])
            assertEquals(512, result["vectorDimension"])
            assertTrue(embeddingVector(result).all(Double::isFinite))
        } finally {
            runtime.close()
        }
    }

    companion object {
        const val MODEL_PATH_SENTINEL = "PHASE5_EMBEDDING_MODEL_PATH_SENTINEL_5D70A1"
        const val TEXT_SENTINEL = "PHASE5_EMBEDDING_TEXT_SENTINEL_26C94B"
    }
}
