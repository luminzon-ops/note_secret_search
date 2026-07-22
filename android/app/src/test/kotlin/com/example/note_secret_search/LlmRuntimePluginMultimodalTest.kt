package com.example.note_secret_search

import io.flutter.plugin.common.MethodCall
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LlmRuntimePluginMultimodalTest {
    @Test
    fun `ensureMultimodalModelReady returns unsupported before reading arguments or calling runtime`() {
        verifyUnsupportedMethod("ensureMultimodalModelReady")
    }

    @Test
    fun `generateMultimodalText returns unsupported before reading arguments or calling runtime`() {
        verifyUnsupportedMethod("generateMultimodalText")
    }

    private fun verifyUnsupportedMethod(method: String) {
        val result = RecordingResult()
        val multimodalRuntime = CountingMultimodalRuntime()
        val plugin = LlmRuntimePlugin(
            runtime = throwingTextRuntime(),
            multimodalRuntime = multimodalRuntime,
            resultDispatcher = ImmediateResultDispatcher(),
        )

        plugin.onMethodCall(
            MethodCall(method, ThrowingMultimodalArgumentsMap()),
            result,
        )

        assertEquals("UNSUPPORTED_CAPABILITY", result.errorCode)
        assertEquals("UNSUPPORTED_CAPABILITY", result.errorMessage)
        assertNull(result.errorDetails)
        assertEquals(1, result.callbackCount.get())
        assertEquals(0, multimodalRuntime.calls)
    }
}

private class CountingMultimodalRuntime : MultimodalLlmRuntimeContract {
    var calls: Int = 0

    override fun ensureModelReady(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
    ): Map<String, Any?> {
        calls += 1
        return emptyMap()
    }

    override fun generateMultimodalText(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
        reasoningEnabled: Boolean,
    ): Map<String, Any?> {
        calls += 1
        return emptyMap()
    }
}

private class ThrowingMultimodalArgumentsMap : AbstractMap<String, Any?>() {
    override val entries: Set<Map.Entry<String, Any?>>
        get() = throw AssertionError("Multimodal arguments must not be inspected.")

    override fun get(key: String): Any? {
        throw AssertionError("Multimodal argument '$key' must not be read.")
    }
}
