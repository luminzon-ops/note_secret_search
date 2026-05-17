package com.example.note_secret_search

import org.nehuatl.llamacpp.LlamaHelper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.net.URI
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking

class GgufLlamaCppBackendTest {
    @Test
    fun `prediction release coordinator defers native release until in-flight prediction finishes`() {
        val calls = mutableListOf<String>()
        val coordinator = PredictionReleaseCoordinator(
            abortPrediction = { calls += "abort" },
            releaseResources = { calls += "release" },
        )

        coordinator.onPredictionStarted()
        coordinator.requestRelease()

        assertEquals(listOf("abort"), calls)

        coordinator.onPredictionFinished()

        assertEquals(listOf("abort", "release"), calls)
    }

    @Test
    fun `prediction release coordinator releases immediately when no prediction is active`() {
        val calls = mutableListOf<String>()
        val coordinator = PredictionReleaseCoordinator(
            abortPrediction = { calls += "abort" },
            releaseResources = { calls += "release" },
        )

        coordinator.requestRelease()

        assertEquals(listOf("abort", "release"), calls)
    }

    @Test
    fun `normalizeModelPathForLlama converts absolute file path into file uri string`() {
        val modelFile = File("/data/user/0/com.example.note_secret_search/files/models/qwen.gguf")

        val normalized = normalizeModelPathForLlama(modelFile)
        val uri = URI(normalized)

        assertTrue("must serialize as a file URI", normalized.startsWith("file:"))
        assertEquals("file", uri.scheme)
        assertTrue(
            "must preserve the Android model path suffix",
            uri.path.endsWith("/data/user/0/com.example.note_secret_search/files/models/qwen.gguf"),
        )
    }

    @Test
    fun `awaitLoadedContextId waits for asynchronous load callback`() = runBlocking {
        val contextId = awaitLoadedContextId(timeoutMillis = 200) { onLoaded ->
            thread {
                Thread.sleep(25)
                onLoaded(42L)
            }
        }

        assertEquals(42L, contextId)
    }

    @Test
    fun `awaitLoadedContextId times out when load callback never arrives`() = runBlocking {
        try {
            awaitLoadedContextId(timeoutMillis = 25) { _ -> }
            fail("Expected awaitLoadedContextId to time out when callback is never invoked.")
        } catch (_: TimeoutCancellationException) {
        }
    }

    @Test
    fun `awaitPredictionTerminalEvent captures terminal event emitted during prediction start`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<String>(
            replay = 0,
            extraBufferCapacity = 1,
        )

        val result = awaitPredictionTerminalEvent<String>(
            timeoutMillis = 200,
            timeoutCleanupMillis = 50,
            predictionScope = predictionScope,
            events = events,
            isTerminal = { it == "done" },
            onTimeout = {},
            onPredictionStarted = {},
            onPredictionFinished = {},
        ) {
            assertTrue(events.tryEmit("done"))
        }

        assertEquals("done", result)
        predictionScope.cancel()
    }

    @Test
    fun `awaitPredictionTerminalEvent times out when terminal event never arrives`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        try {
            awaitPredictionTerminalEvent<String>(
                timeoutMillis = 25,
                timeoutCleanupMillis = 50,
                predictionScope = predictionScope,
                events = MutableSharedFlow<String>(replay = 0, extraBufferCapacity = 1),
                isTerminal = { it == "done" },
                onTimeout = {},
                onPredictionStarted = {},
                onPredictionFinished = {},
            ) {
            }
            fail("Expected awaitPredictionTerminalEvent to time out when terminal event never arrives.")
        } catch (_: TimeoutCancellationException) {
        } finally {
            predictionScope.cancel()
        }
    }

    @Test
    fun `awaitPredictionTerminalEvent aborts on timeout and waits briefly for prediction cleanup`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val started = AtomicBoolean(false)
        val timedOut = AtomicBoolean(false)
        val startedAt = System.nanoTime()
        val elapsedMillis = try {
            awaitPredictionTerminalEvent<String>(
                timeoutMillis = 25,
                timeoutCleanupMillis = 250,
                predictionScope = predictionScope,
                events = MutableSharedFlow<String>(replay = 0, extraBufferCapacity = 1),
                isTerminal = { it == "done" },
                onTimeout = {
                    timedOut.set(true)
                },
                onPredictionStarted = {},
                onPredictionFinished = {},
            ) {
                started.set(true)
                Thread.sleep(150)
            }
            fail("Expected awaitPredictionTerminalEvent to time out while prediction start is still blocking.")
            -1L
        } catch (_: TimeoutCancellationException) {
            (System.nanoTime() - startedAt) / 1_000_000
        } finally {
            predictionScope.cancel()
        }

        assertTrue("blocking prediction start should have been entered", started.get())
        assertTrue("timeout callback should abort the in-flight prediction", timedOut.get())
        assertTrue(
            "cleanup wait should stay bounded while allowing prediction unwind, elapsed=${'$'}elapsedMillis ms",
            elapsedMillis in 120..260,
        )
    }

    @Test
    fun `generate disables partial completion for Huawei stability experiment`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaHelper.LLMEvent>(
            replay = 0,
            extraBufferCapacity = 2,
        )
        val helper = RecordingLlamaHelperClient(
            events = events,
            predictionEvents = listOf(
                LlamaHelper.LLMEvent.Ongoing("stable result", 1),
                LlamaHelper.LLMEvent.Done("", 1, 0L),
            ),
        )
        val backend = GgufLlamaCppBackend(
            helper = helper,
            predictionScope = predictionScope,
            eventFlow = events,
        )
        val session = LocalLlmBackendSession(
            modelId = "phi-local",
            modelPath = "/data/user/0/com.example.note_secret_search/files/models/smollm.gguf",
            backendName = "gguf-llama-cpp",
            handle = 7L,
            backend = backend,
        )

        val result = backend.generate(
            session = session,
            prompt = "hello-stability-check",
            maxTokens = 256,
        )

        assertEquals("stable result", result.text)
        assertEquals("stop", result.finishReason)
        assertFalse(
            "partial completion should be disabled for the single-variable Huawei stability experiment.",
            helper.lastEmitPartialCompletion,
        )
        predictionScope.cancel()
    }

    @Test
    fun `generate returns latest ongoing text when done event is empty`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaHelper.LLMEvent>(
            replay = 0,
            extraBufferCapacity = 2,
        )
        val helper = RecordingLlamaHelperClient(
            events = events,
            predictionEvents = listOf(
                LlamaHelper.LLMEvent.Ongoing("partial local reply", 1),
                LlamaHelper.LLMEvent.Done("", 1, 0L),
            ),
        )
        val backend = GgufLlamaCppBackend(
            helper = helper,
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

        val result = backend.generate(
            session = session,
            prompt = "hello",
            maxTokens = 96,
        )

        assertEquals("partial local reply", result.text)
        assertEquals("stop", result.finishReason)
        predictionScope.cancel()
    }

    @Test
    fun `load uses reduced context length for Huawei stability experiment`() {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaHelper.LLMEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val helper = RecordingLlamaHelperClient(events)
        val backend = GgufLlamaCppBackend(
            helper = helper,
            predictionScope = predictionScope,
            eventFlow = events,
        )

        backend.load(
            modelId = "smollm-huawei",
            file = File("/data/user/0/com.example.note_secret_search/files/models/smollm.gguf"),
        )

        assertEquals(
            "context length should be reduced to lower native KV-cache pressure on Huawei.",
            1024,
            helper.lastContextLength,
        )
        predictionScope.cancel()
    }

    @Test
    fun `huawei conservative generation config keeps context length and disables partial completion`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaHelper.LLMEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val helper = RecordingLlamaHelperClient(events)
        val backend = GgufLlamaCppBackend(
            helper = helper,
            predictionScope = predictionScope,
            eventFlow = events,
        )
        val session = backend.load(
            modelId = "smollm-huawei",
            file = File("/data/user/0/com.example.note_secret_search/files/models/smollm.gguf"),
        )

        backend.generate(
            session = session,
            prompt = "hello-stability-check",
            maxTokens = 96,
            config = LocalLlmGenerationConfig(
                contextLength = 1024,
                maxOutputTokens = 96,
                maxPromptChars = 1200,
                conservativeMode = true,
                emitPartialCompletion = false,
            ),
        )

        assertEquals(1024, helper.lastContextLength)
        assertFalse(helper.lastEmitPartialCompletion)
        assertEquals(96, helper.lastRequestedMaxTokens)
        predictionScope.cancel()
    }

    @Test
    fun `generate truncates prompt to conservative maxPromptChars before native predict`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaHelper.LLMEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val helper = RecordingLlamaHelperClient(events)
        val backend = GgufLlamaCppBackend(
            helper = helper,
            predictionScope = predictionScope,
            eventFlow = events,
        )
        val session = LocalLlmBackendSession(
            modelId = "phi-local",
            modelPath = "/data/user/0/com.example.note_secret_search/files/models/smollm.gguf",
            backendName = "gguf-llama-cpp",
            handle = 7L,
            backend = backend,
        )

        backend.generate(
            session = session,
            prompt = "a".repeat(20),
            maxTokens = 96,
            config = LocalLlmGenerationConfig(
                contextLength = 1024,
                maxOutputTokens = 96,
                maxPromptChars = 8,
                conservativeMode = true,
                emitPartialCompletion = false,
            ),
        )

        assertEquals("aaaaaaaa", helper.lastPrompt)
        predictionScope.cancel()
    }
}

private class RecordingLlamaHelperClient(
    private val events: MutableSharedFlow<LlamaHelper.LLMEvent>,
    private val predictionEvents: List<LlamaHelper.LLMEvent> = listOf(
        LlamaHelper.LLMEvent.Done("stable result", 1, 0L),
    ),
) : LlamaHelperClient {
    var lastEmitPartialCompletion: Boolean = true
    var lastContextLength: Int = 0
    var lastRequestedMaxTokens: Int = 0
    var lastPrompt: String = ""

    override fun load(path: String, contextLength: Int, onLoaded: (Long) -> Unit) {
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
