package com.example.note_secret_search

import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LlamaContextAdapterTest {
    @Test
    fun `production adapter wraps the silent bridge context`() {
        val adapterClass = Class.forName(
            "com.example.note_secret_search.AndroidLlamaNativeContext",
        )
        val delegateType = adapterClass.declaredConstructors
            .single()
            .parameterTypes
            .single()

        assertEquals(
            "com.example.nssllama.SilentLlamaContext",
            delegateType.name,
        )
    }

    @Test
    fun `load opens a file descriptor and uses a fixed logical model name`() {
        val file = File.createTempFile("MODEL_PATH_SENTINEL", ".gguf").apply {
            deleteOnExit()
            writeText("fixture")
        }
        val descriptor = RecordingLlamaModelDescriptor(fd = 73)
        var openedFile: File? = null
        var capturedContextId: Int? = null
        var capturedParams: Map<String, Any>? = null
        val nativeContext = RecordingLlamaNativeContext()
        val client = DirectLlamaContextClient(
            descriptorOpener = LlamaModelDescriptorOpener { candidate ->
                openedFile = candidate
                descriptor
            },
            contextFactory = LlamaNativeContextFactory { contextId, params ->
                capturedContextId = contextId
                capturedParams = params
                nativeContext
            },
            events = MutableSharedFlow(extraBufferCapacity = 4),
        )

        var loadedContextId: Long? = null
        client.load(file = file, contextLength = 1024) { contextId ->
            loadedContextId = contextId
        }

        assertEquals(file, openedFile)
        assertEquals(capturedContextId?.toLong(), loadedContextId)
        assertEquals(73, capturedParams?.get("model_fd"))
        assertEquals(FIXED_LOGICAL_MODEL_NAME, capturedParams?.get("model"))
        assertEquals(1024, capturedParams?.get("n_ctx"))
        assertEquals(false, capturedParams?.get("use_mmap"))
        assertEquals(false, capturedParams?.get("use_mlock"))
        assertFalse(capturedParams.toString().contains(file.absolutePath))

        client.abort()
        client.release()

        assertTrue(nativeContext.stopped)
        assertTrue(descriptor.closed)
        assertTrue(nativeContext.released)
    }
}

private class RecordingLlamaModelDescriptor(
    override val fd: Int,
) : LlamaModelDescriptor {
    var closed = false

    override fun close() {
        closed = true
    }
}

private class RecordingLlamaNativeContext : LlamaNativeContext {
    var stopped = false
    var released = false

    override fun setTokenCallback(callback: (String) -> Unit) {
    }

    override fun completion(params: Map<String, Any>): Map<String, Any?> {
        return mapOf("text" to "fixture")
    }

    override fun stopCompletion() {
        stopped = true
    }

    override fun release() {
        released = true
    }
}
