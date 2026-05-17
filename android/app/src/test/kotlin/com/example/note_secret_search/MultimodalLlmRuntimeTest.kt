package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MultimodalLlmRuntimeTest {
    @Test
    fun `ensure model ready reports missing mmproj`() {
        val runtime = FallbackMultimodalLlmRuntime()
        val payload = runtime.ensureModelReady(
            modelId = "minicpm_v_4_6_q4_k_m",
            modelPath = "/models/model.gguf",
            mmprojPath = "",
        )

        assertEquals("missing_mmproj", payload["status"])
        assertEquals(false, payload["ready"])
        assertEquals("fallback_no_mtmd", payload["backend"])
    }

    @Test
    fun `generate reports native runtime unavailable before mtmd backend is installed`() {
        val runtime = FallbackMultimodalLlmRuntime()
        val payload = runtime.generateMultimodalText(
            modelId = "minicpm_v_4_6_q4_k_m",
            modelPath = "/models/model.gguf",
            mmprojPath = "/models/mmproj.gguf",
            imagePath = "/cache/input.jpg",
            prompt = "Describe it",
            config = LocalLlmGenerationConfig(),
            reasoningEnabled = false,
        )

        assertEquals("runtime_unavailable", payload["status"])
        assertFalse(payload["ready"] as Boolean)
        assertEquals("fallback_no_mtmd", payload["backend"])
    }
}
