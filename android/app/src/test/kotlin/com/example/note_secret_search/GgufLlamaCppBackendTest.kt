package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

class GgufLlamaCppBackendTest {
    @Test
    fun `prediction release coordinator defers native release until in-flight prediction finishes`() {
        val calls = java.util.Collections.synchronizedList(mutableListOf<String>())
        val abortEntered = CountDownLatch(1)
        val releaseReturned = CountDownLatch(1)
        val coordinator = PredictionReleaseCoordinator(
            abortPrediction = {
                calls += "abort"
                abortEntered.countDown()
            },
            releaseResources = { calls += "release" },
        )

        assertTrue(coordinator.tryRegisterPrediction())
        val releaseThread = thread(start = true) {
            coordinator.requestRelease()
            releaseReturned.countDown()
        }

        assertTrue(abortEntered.await(1, TimeUnit.SECONDS))
        assertEquals(listOf("abort"), calls)
        assertFalse(releaseReturned.await(50, TimeUnit.MILLISECONDS))

        coordinator.onPredictionFinished()

        assertTrue(releaseReturned.await(1, TimeUnit.SECONDS))
        releaseThread.join(1_000)
        assertFalse(releaseThread.isAlive)
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
    fun `prediction release coordinator rejects registration after release begins`() {
        val abortEntered = CountDownLatch(1)
        val allowAbortReturn = CountDownLatch(1)
        val released = CountDownLatch(1)
        val coordinator = PredictionReleaseCoordinator(
            abortPrediction = {
                abortEntered.countDown()
                allowAbortReturn.await(2, TimeUnit.SECONDS)
            },
            releaseResources = {
                released.countDown()
            },
        )

        val releaseThread = thread(start = true) {
            coordinator.requestRelease()
        }

        assertTrue(abortEntered.await(1, TimeUnit.SECONDS))
        assertFalse(coordinator.tryRegisterPrediction())

        allowAbortReturn.countDown()
        releaseThread.join(1_000)

        assertFalse(releaseThread.isAlive)
        assertTrue(released.await(1, TimeUnit.SECONDS))
    }

    @Test
    fun `backend cancellation delegates directly to native abort`() {
        val fixture = createGgufBackendTestFixture(
            predictionEvents = listOf(LlamaRuntimeEvent.Done("unused")),
        )
        try {
            fixture.backend.cancel(fixture.session)

            assertEquals(1, fixture.client.abortCalls)
        } finally {
            fixture.close()
        }
    }

    @Test
    fun `load predict and release stay on the native caller thread`() {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaRuntimeEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val client = RecordingLlamaContextClient(events)
        val backend = GgufLlamaCppBackend(
            client = client,
            predictionScope = predictionScope,
            eventFlow = events,
        )
        val executor = Executors.newSingleThreadExecutor(
            ThreadFactory { runnable -> Thread(runnable, "fixture-native-worker") },
        )
        val model = File.createTempFile("thread-owner", ".gguf").apply {
            deleteOnExit()
        }

        try {
            val callerThreadId = executor.submit<Long> {
                val threadId = Thread.currentThread().id
                val session = backend.load("model-thread", model)
                backend.generate(
                    session = session,
                    prompt = "thread ownership",
                    maxTokens = 16,
                )
                backend.release(session)
                threadId
            }.get(2, TimeUnit.SECONDS)

            assertEquals(listOf(callerThreadId), client.loadThreadIds)
            assertEquals(listOf(callerThreadId), client.predictThreadIds)
            assertEquals(listOf(callerThreadId), client.releaseThreadIds)
        } finally {
            predictionScope.cancel()
            executor.shutdownNow()
        }
    }

    @Test
    fun `backend enforces native prompt hard cap`() {
        val fixture = createGgufBackendTestFixture(
            predictionEvents = listOf(LlamaRuntimeEvent.Done("unused")),
        )
        try {
            try {
                fixture.backend.generate(
                    session = fixture.session,
                    prompt = "x".repeat(LOCAL_LLM_MAX_PROMPT_CHARS + 1),
                    maxTokens = 16,
                    config = LocalLlmGenerationConfig(maxPromptChars = 4_000),
                )
                fail("Expected native prompt hard cap to reject oversized input.")
            } catch (error: IllegalArgumentException) {
                assertEquals("Prompt exceeds maxPromptChars.", error.message)
            }
            assertEquals("", fixture.client.lastPrompt)
        } finally {
            fixture.close()
        }
    }

    @Test
    fun `awaitLoadedContextId waits for asynchronous load callback`() = runBlocking {
        val loadScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        try {
            val contextId = awaitLoadedContextId(
                timeoutMillis = 200,
                loadScope = loadScope,
                onLateLoaded = {},
            ) { onLoaded ->
                thread {
                    Thread.sleep(25)
                    onLoaded(42L)
                }
            }

            assertEquals(42L, contextId)
        } finally {
            loadScope.cancel()
        }
    }

    @Test
    fun `awaitLoadedContextId times out when load callback never arrives`() = runBlocking {
        val loadScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        try {
            awaitLoadedContextId(
                timeoutMillis = 25,
                loadScope = loadScope,
                onLateLoaded = {},
            ) { _ -> }
            fail("Expected awaitLoadedContextId to time out when callback is never invoked.")
        } catch (_: TimeoutCancellationException) {
        } finally {
            loadScope.cancel()
        }
    }

    @Test
    fun `awaitLoadedContextId times out while native load blocks and cleans late completion`() = runBlocking {
        val loadScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val loadEntered = CountDownLatch(1)
        val allowLoadReturn = CountDownLatch(1)
        val lateCleanup = CountDownLatch(1)
        val outcome = async(Dispatchers.Default) {
            try {
                awaitLoadedContextId(
                    timeoutMillis = 40,
                    loadScope = loadScope,
                    onLateLoaded = {
                        lateCleanup.countDown()
                    },
                ) { onLoaded ->
                    loadEntered.countDown()
                    allowLoadReturn.await(2, TimeUnit.SECONDS)
                    onLoaded(99L)
                }
                "loaded"
            } catch (_: TimeoutCancellationException) {
                "timed_out"
            }
        }

        try {
            assertTrue(loadEntered.await(1, TimeUnit.SECONDS))
            assertEquals(
                "timed_out",
                withTimeoutOrNull(250) {
                    outcome.await()
                },
            )
        } finally {
            allowLoadReturn.countDown()
        }

        assertTrue(lateCleanup.await(1, TimeUnit.SECONDS))
        loadScope.cancel()
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
            tryRegisterPrediction = { true },
            onPredictionFinished = {},
        ) {
            assertTrue(events.tryEmit("done"))
        }

        assertEquals("done", result)
        predictionScope.cancel()
    }

    @Test
    fun `awaitPredictionTerminalEvent ignores stale terminal event identity`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaRuntimeEvent>(
            replay = 0,
            extraBufferCapacity = 2,
        )

        val result = awaitPredictionTerminalEvent(
            timeoutMillis = 200,
            timeoutCleanupMillis = 50,
            predictionScope = predictionScope,
            events = events,
            isTerminal = { event ->
                event.generationId == 2L &&
                    (event is LlamaRuntimeEvent.Done || event is LlamaRuntimeEvent.Error)
            },
            onTimeout = {},
            tryRegisterPrediction = { true },
            onPredictionFinished = {},
        ) {
            assertTrue(events.tryEmit(LlamaRuntimeEvent.Done("stale", generationId = 1L)))
            assertTrue(events.tryEmit(LlamaRuntimeEvent.Done("current", generationId = 2L)))
        }

        assertEquals(LlamaRuntimeEvent.Done("current", generationId = 2L), result)
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
                tryRegisterPrediction = { true },
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
                tryRegisterPrediction = { true },
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
    fun `caller-thread prediction timeout aborts while native call is blocked`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val predictionEntered = CountDownLatch(1)
        val allowPredictionReturn = CountDownLatch(1)
        val timeoutEntered = CountDownLatch(1)
        val outcome = async(Dispatchers.Default) {
            try {
                awaitPredictionTerminalEvent<String>(
                    timeoutMillis = 30,
                    timeoutCleanupMillis = 100,
                    predictionScope = predictionScope,
                    events = MutableSharedFlow(replay = 0, extraBufferCapacity = 1),
                    isTerminal = { it == "done" },
                    onTimeout = {
                        timeoutEntered.countDown()
                    },
                    tryRegisterPrediction = { true },
                    onPredictionFinished = {},
                    startOnCallerThread = true,
                ) {
                    predictionEntered.countDown()
                    allowPredictionReturn.await(2, TimeUnit.SECONDS)
                }
                "completed"
            } catch (_: TimeoutCancellationException) {
                "timed_out"
            }
        }

        try {
            assertTrue(predictionEntered.await(1, TimeUnit.SECONDS))
            assertTrue(
                "timeout must invoke abort while the caller-thread native call is blocked",
                timeoutEntered.await(250, TimeUnit.MILLISECONDS),
            )
        } finally {
            allowPredictionReturn.countDown()
        }

        assertEquals("timed_out", outcome.await())
        predictionScope.cancel()
    }

    @Test
    fun `awaitPredictionTerminalEvent registers before queued native work starts`() = runBlocking {
        val executor = Executors.newSingleThreadExecutor()
        val dispatcher = executor.asCoroutineDispatcher()
        val predictionScope = CoroutineScope(dispatcher + SupervisorJob())
        val blockerEntered = CountDownLatch(1)
        val allowPredictionWorker = CountDownLatch(1)
        val registered = CountDownLatch(1)
        val events = MutableSharedFlow<String>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        predictionScope.launch {
            blockerEntered.countDown()
            allowPredictionWorker.await(2, TimeUnit.SECONDS)
        }

        assertTrue(blockerEntered.await(1, TimeUnit.SECONDS))
        val result = async(Dispatchers.Default) {
            awaitPredictionTerminalEvent(
                timeoutMillis = 1_000,
                timeoutCleanupMillis = 100,
                predictionScope = predictionScope,
                events = events,
                isTerminal = { it == "done" },
                onTimeout = {},
                tryRegisterPrediction = {
                    registered.countDown()
                    true
                },
                onPredictionFinished = {},
            ) {
                check(events.tryEmit("done"))
            }
        }

        try {
            assertTrue(
                "prediction must register before native work is queued",
                registered.await(200, TimeUnit.MILLISECONDS),
            )
        } finally {
            allowPredictionWorker.countDown()
        }

        assertEquals("done", result.await())
        predictionScope.cancel()
        dispatcher.close()
        executor.shutdownNow()
        Unit
    }

    @Test
    fun `generate disables partial completion and rejects empty final text`() = runBlocking {
        val fixture = createGgufBackendTestFixture(
            predictionEvents = listOf(
                LlamaRuntimeEvent.Ongoing("partial"),
                LlamaRuntimeEvent.Done(""),
            ),
        )

        try {
            try {
                fixture.backend.generate(
                    session = fixture.session,
                    prompt = "hello-stability-check",
                    maxTokens = 256,
                    config = LocalLlmGenerationConfig(
                        emitPartialCompletion = true,
                    ),
                )
                fail("Expected empty final text to be rejected.")
            } catch (error: IllegalArgumentException) {
                assertEquals("Backend returned empty text.", error.message)
            }

            assertFalse(
                "partial completion must stay disabled even when requested by config.",
                fixture.client.lastEmitPartialCompletion,
            )
        } finally {
            fixture.close()
        }
    }

    @Test
    fun `load uses reduced context length for Huawei stability experiment`() {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaRuntimeEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val client = RecordingLlamaContextClient(events)
        val backend = GgufLlamaCppBackend(
            client = client,
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
            client.lastContextLength,
        )
        predictionScope.cancel()
    }

    @Test
    fun `huawei conservative generation config keeps context length and disables partial completion`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaRuntimeEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val client = RecordingLlamaContextClient(events)
        val backend = GgufLlamaCppBackend(
            client = client,
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

        assertEquals(1024, client.lastContextLength)
        assertFalse(client.lastEmitPartialCompletion)
        assertEquals(96, client.lastRequestedMaxTokens)
        predictionScope.cancel()
    }

    @Test
    fun `generate rejects prompt beyond maxPromptChars before native predict`() = runBlocking {
        val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val events = MutableSharedFlow<LlamaRuntimeEvent>(
            replay = 0,
            extraBufferCapacity = 1,
        )
        val client = RecordingLlamaContextClient(events)
        val backend = GgufLlamaCppBackend(
            client = client,
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

        try {
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
            fail("Expected prompt budget validation to fail.")
        } catch (error: IllegalArgumentException) {
            assertEquals("Prompt exceeds maxPromptChars.", error.message)
        }

        assertEquals("", client.lastPrompt)
        predictionScope.cancel()
    }
}
