package com.example.note_secret_search

import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow

internal class RecordingLlamaContextClient(
    private val events: MutableSharedFlow<LlamaRuntimeEvent>,
    private val predictionEvents: List<LlamaRuntimeEvent> = listOf(
        LlamaRuntimeEvent.Done("stable result"),
    ),
) : LlamaContextClient {
    var lastEmitPartialCompletion: Boolean = true
    var lastContextLength: Int = 0
    var lastRequestedMaxTokens: Int = 0
    var lastPrompt: String = ""

    override fun load(file: File, contextLength: Int, onLoaded: (Long) -> Unit) {
        lastContextLength = contextLength
        onLoaded(7L)
    }

    override fun predict(
        prompt: String,
        emitPartialCompletion: Boolean,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ) {
        lastEmitPartialCompletion = emitPartialCompletion
        lastRequestedMaxTokens = maxTokens
        lastPrompt = prompt
        predictionEvents.forEach { event ->
            check(events.tryEmit(event))
        }
    }

    override fun abort() {
    }

    override fun release() {
    }
}

internal class GgufBackendTestFixture(
    val client: RecordingLlamaContextClient,
    val backend: GgufLlamaCppBackend,
    val session: LocalLlmBackendSession,
    private val predictionScope: CoroutineScope,
) {
    fun close() {
        predictionScope.cancel()
    }
}

internal fun createGgufBackendTestFixture(
    predictionEvents: List<LlamaRuntimeEvent>,
): GgufBackendTestFixture {
    val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val events = MutableSharedFlow<LlamaRuntimeEvent>(
        replay = 0,
        extraBufferCapacity = predictionEvents.size,
    )
    val client = RecordingLlamaContextClient(
        events = events,
        predictionEvents = predictionEvents,
    )
    val backend = GgufLlamaCppBackend(
        client = client,
        predictionScope = predictionScope,
        eventFlow = events,
    )
    val session = LocalLlmBackendSession(
        modelId = "smollm-huawei",
        modelPath = "/data/user/0/com.example.note_secret_search/files/models/smollm.gguf",
        backendName = "gguf-llama-cpp",
        handle = 7L,
        backend = backend,
    )
    return GgufBackendTestFixture(
        client = client,
        backend = backend,
        session = session,
        predictionScope = predictionScope,
    )
}
