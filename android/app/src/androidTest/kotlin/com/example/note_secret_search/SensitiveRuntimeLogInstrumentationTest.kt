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
class SensitiveRuntimeLogInstrumentationTest {
    @Test
    fun localGenerationDoesNotRequireSensitiveLogValues() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val sourceModel = findInstalledModel(context.filesDir)
        val sentinelDirectory = File(context.filesDir, "runtime-log-smoke").apply {
            mkdirs()
        }
        val sentinelModel = File(
            sentinelDirectory,
            "$MODEL_PATH_SENTINEL.gguf",
        )
        if (sentinelModel.exists()) {
            assertTrue(sentinelModel.delete())
        }
        sourceModel.copyTo(sentinelModel)

        val runtime = LocalLlmRuntime(
            context = context,
            sessionManager = LlmModelSessionManager(),
        )
        try {
            val ready = runtime.ensureModelReady(
                modelId = "phase1-log-smoke",
                modelPath = sentinelModel.absolutePath,
            )
            assertEquals("ready", ready["status"])

            val result = runtime.generateText(
                modelId = "phase1-log-smoke",
                modelPath = sentinelModel.absolutePath,
                prompt = "$PROMPT_SENTINEL Reply with OK.",
                usedPrivateContext = true,
                config = LocalLlmGenerationConfig(
                    contextLength = HUAWEI_SAFE_CONTEXT_LENGTH,
                    maxOutputTokens = 8,
                    maxPromptChars = 160,
                    conservativeMode = true,
                    emitPartialCompletion = false,
                    seed = 42,
                ),
            )

            assertEquals("ready", result["status"])
            assertFalse((result["text"] as? String).isNullOrBlank())
        } finally {
            runtime.releaseModel("phase1-log-smoke")
            assertTrue(sentinelModel.delete())
        }
    }

    private fun findInstalledModel(filesDirectory: File): File {
        val modelsDirectory = File(filesDirectory, "models")
        val candidates = modelsDirectory.walkTopDown()
            .filter { file -> file.isFile && file.extension.equals("gguf", ignoreCase = true) }
            .sortedBy { file ->
                if (file.name.contains("smollm", ignoreCase = true)) {
                    0
                } else {
                    1
                }
            }
            .toList()
        assertTrue("Expected an installed GGUF model for the device smoke test.", candidates.isNotEmpty())
        return candidates.first()
    }

    companion object {
        const val MODEL_PATH_SENTINEL = "PHASE1_MODEL_PATH_SENTINEL_91F37D"
        const val PROMPT_SENTINEL = "PHASE1_PROMPT_SENTINEL_4B8C2A"
    }
}
