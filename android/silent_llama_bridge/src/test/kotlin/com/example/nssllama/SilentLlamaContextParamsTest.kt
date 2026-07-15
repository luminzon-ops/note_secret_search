package com.example.nssllama

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SilentLlamaContextParamsTest {
    @Test
    fun `init arguments match current AAR defaults`() {
        val arguments = decodeSilentLlamaInitArguments(
            mapOf(
                "model" to "local-model.gguf",
                "model_fd" to 73,
                "use_mmap" to false,
            ),
        )

        assertEquals(73, arguments.modelFd)
        assertFalse(arguments.embedding)
        assertEquals(512, arguments.contextSize)
        assertEquals(512, arguments.batchSize)
        assertEquals(0, arguments.threadCount)
        assertEquals(0, arguments.gpuLayerCount)
        assertTrue(arguments.useMlock)
        assertFalse(arguments.useMmap)
        assertFalse(arguments.vocabOnly)
        assertEquals("", arguments.loraPath)
        assertEquals(1.0f, arguments.loraScale)
        assertEquals(0.0f, arguments.ropeFrequencyBase)
        assertEquals(0.0f, arguments.ropeFrequencyScale)
    }

    @Test
    fun `init arguments require the logical model key`() {
        assertThrows(IllegalArgumentException::class.java) {
            decodeSilentLlamaInitArguments(mapOf("model_fd" to 73))
        }
    }

    @Test
    fun `completion arguments match current AAR defaults`() {
        val arguments = decodeSilentLlamaCompletionArguments(
            mapOf("prompt" to "Hello"),
        )

        assertEquals("Hello", arguments.prompt)
        assertEquals("", arguments.grammar)
        assertEquals(0.7f, arguments.temperature)
        assertEquals(0, arguments.threadCount)
        assertEquals(-1, arguments.predictionCount)
        assertEquals(0, arguments.probabilityCount)
        assertEquals(64, arguments.penaltyLastN)
        assertEquals(1.0f, arguments.penaltyRepeat)
        assertEquals(0.0f, arguments.penaltyFrequency)
        assertEquals(0.0f, arguments.penaltyPresence)
        assertEquals(0.0f, arguments.mirostat)
        assertEquals(5.0f, arguments.mirostatTau)
        assertEquals(0.1f, arguments.mirostatEta)
        assertFalse(arguments.penalizeNewline)
        assertEquals(40, arguments.topK)
        assertEquals(0.95f, arguments.topP)
        assertEquals(0.05f, arguments.minP)
        assertEquals(0.0f, arguments.xtcThreshold)
        assertEquals(0.0f, arguments.xtcProbability)
        assertEquals(1.0f, arguments.tailFreeSamplingZ)
        assertEquals(1.0f, arguments.typicalP)
        assertEquals(-1, arguments.seed)
        assertArrayEquals(emptyArray<String>(), arguments.stop)
        assertFalse(arguments.ignoreEos)
        assertEquals(0, arguments.logitBias.size)
        assertFalse(arguments.emitPartialCompletion)
    }

    @Test
    fun `completion arguments require a prompt`() {
        assertThrows(IllegalArgumentException::class.java) {
            decodeSilentLlamaCompletionArguments(emptyMap())
        }
    }
}
