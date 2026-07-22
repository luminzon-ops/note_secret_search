package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Collections
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class LlmLifecycleCoordinatorTest {
    @Test
    fun `matching concurrent readiness joins one native load`() {
        val model = temporaryModel("coalesced-load")
        val backend = LifecycleRecordingBackend(
            loadEntered = CountDownLatch(1),
            allowLoadReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            val first = coordinator.ensureModelReadyAsync("model-a", model.absolutePath)
            assertTrue(backend.loadEntered.await(1, TimeUnit.SECONDS))
            val second = coordinator.ensureModelReadyAsync("model-a", model.absolutePath)

            assertEquals(1, backend.loadCalls.get())
            assertTrue(coordinator.snapshot().state is LlmLifecycleState.Loading)
            backend.allowLoadReturn.countDown()

            assertEquals("ready", first.get(1, TimeUnit.SECONDS)["status"])
            assertEquals("ready", second.get(1, TimeUnit.SECONDS)["status"])
            assertEquals(1, backend.loadCalls.get())
            assertEquals(1L, coordinator.snapshot().sessionEpoch)
            assertTrue(coordinator.snapshot().state is LlmLifecycleState.Ready)
        } finally {
            backend.allowLoadReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `model switch releases previous session before loading next identity`() {
        val firstModel = temporaryModel("switch-a")
        val secondModel = temporaryModel("switch-b")
        val backend = LifecycleRecordingBackend()
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", firstModel.absolutePath)
            coordinator.ensureModelReady("model-b", secondModel.absolutePath)

            assertEquals(
                listOf(
                    "load:${firstModel.canonicalPath}",
                    "release:${firstModel.canonicalPath}",
                    "load:${secondModel.canonicalPath}",
                ),
                backend.events.take(3),
            )
            val state = coordinator.snapshot().state as LlmLifecycleState.Ready
            assertEquals("model-b", state.identity.modelId)
            assertEquals(2L, state.epoch)
        } finally {
            coordinator.close()
        }
    }

    @Test
    fun `second generation is rejected as busy while first generation owns native runtime`() {
        val model = temporaryModel("busy-generation")
        val backend = LifecycleRecordingBackend(
            generateEntered = CountDownLatch(1),
            allowGenerateReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val first = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-1",
                prompt = "first",
                usedPrivateContext = false,
            )
            assertTrue(backend.generateEntered.await(1, TimeUnit.SECONDS))

            val second = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-2",
                prompt = "second",
                usedPrivateContext = false,
            )

            assertFutureFailure(second, LlmRuntimeErrorCode.BUSY)
            backend.allowGenerateReturn.countDown()
            assertEquals("generated:first", first.get(1, TimeUnit.SECONDS)["text"])
            assertEquals(listOf("first"), backend.prompts)
            assertEquals(1, backend.nativeThreadNames.distinct().size)
        } finally {
            backend.allowGenerateReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `release acknowledgement waits for native free`() {
        val model = temporaryModel("release-ack")
        val backend = LifecycleRecordingBackend(
            releaseEntered = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val release = coordinator.releaseModelAsync("model-a")

            assertTrue(backend.releaseEntered.await(1, TimeUnit.SECONDS))
            assertFalse(release.isDone)
            assertTrue(coordinator.snapshot().state is LlmLifecycleState.Releasing)

            backend.allowReleaseReturn.countDown()
            release.get(1, TimeUnit.SECONDS)
            assertEquals(LlmLifecycleState.Empty, coordinator.snapshot().state)
        } finally {
            backend.allowReleaseReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `generation failure frees stale session before reporting stable error`() {
        val model = temporaryModel("generation-failure")
        val backend = LifecycleRecordingBackend(
            generationFailure = IllegalStateException("PROMPT_SENTINEL"),
        )
        val coordinator = coordinator(backend)

        try {
            val result = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-failure",
                prompt = "private prompt",
                usedPrivateContext = true,
            )

            assertFutureFailure(result, LlmRuntimeErrorCode.GENERATION_FAILED)
            assertEquals(1, backend.releaseCalls.get())
            assertEquals(LlmLifecycleState.Empty, coordinator.snapshot().state)
        } finally {
            coordinator.close()
        }
    }

    @Test
    fun `cancel uses control lane and waits for generation to unwind before cancelled result`() {
        val model = temporaryModel("cancel-generation")
        val backend = LifecycleRecordingBackend(
            generateEntered = CountDownLatch(1),
            allowGenerateReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val generation = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-cancel",
                prompt = "cancel me",
                usedPrivateContext = false,
            )
            assertTrue(backend.generateEntered.await(1, TimeUnit.SECONDS))

            assertTrue(coordinator.cancelGenerationAsync("request-cancel").get(1, TimeUnit.SECONDS))
            assertTrue(backend.cancelEntered.await(1, TimeUnit.SECONDS))
            assertFutureFailure(generation, LlmRuntimeErrorCode.CANCELLED)

            assertEquals(1, backend.cancelCalls.get())
            assertEquals(0, backend.releaseCalls.get())
            assertTrue(coordinator.snapshot().state is LlmLifecycleState.Ready)
            assertTrue(backend.controlThreadNames.single() !in backend.nativeThreadNames)
            assertFalse(coordinator.cancelGeneration("request-cancel"))
        } finally {
            backend.allowGenerateReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `release during generation cancels then acknowledges only after native free`() {
        val model = temporaryModel("release-generation")
        val backend = LifecycleRecordingBackend(
            generateEntered = CountDownLatch(1),
            allowGenerateReturn = CountDownLatch(1),
            releaseEntered = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val generation = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-release",
                prompt = "release me",
                usedPrivateContext = false,
            )
            assertTrue(backend.generateEntered.await(1, TimeUnit.SECONDS))

            val release = coordinator.releaseModelAsync("model-a")
            assertTrue(backend.cancelEntered.await(1, TimeUnit.SECONDS))
            assertTrue(backend.releaseEntered.await(1, TimeUnit.SECONDS))
            assertFalse(release.isDone)
            assertFalse(generation.isDone)

            backend.allowReleaseReturn.countDown()
            release.get(1, TimeUnit.SECONDS)
            assertFutureFailure(generation, LlmRuntimeErrorCode.CANCELLED)
            assertEquals(1, backend.cancelCalls.get())
            assertEquals(1, backend.releaseCalls.get())
            assertEquals(LlmLifecycleState.Empty, coordinator.snapshot().state)
        } finally {
            backend.allowGenerateReturn.countDown()
            backend.allowReleaseReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `repeated release joins one native free acknowledgement`() {
        val model = temporaryModel("repeated-release")
        val backend = LifecycleRecordingBackend(
            releaseEntered = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val first = coordinator.releaseModelAsync("model-a")
            assertTrue(backend.releaseEntered.await(1, TimeUnit.SECONDS))
            val second = coordinator.releaseModelAsync("model-a")

            assertFalse(first.isDone)
            assertFalse(second.isDone)
            backend.allowReleaseReturn.countDown()
            first.get(1, TimeUnit.SECONDS)
            second.get(1, TimeUnit.SECONDS)

            assertEquals(1, backend.releaseCalls.get())
            coordinator.releaseModel("model-a")
            assertEquals(1, backend.releaseCalls.get())
        } finally {
            backend.allowReleaseReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `release while generation is loading cancels request before predict and frees loaded session`() {
        val model = temporaryModel("release-during-load")
        val backend = LifecycleRecordingBackend(
            loadEntered = CountDownLatch(1),
            allowLoadReturn = CountDownLatch(1),
            releaseEntered = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            val generation = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-loading",
                prompt = "must not reach native predict",
                usedPrivateContext = false,
            )
            assertTrue(backend.loadEntered.await(1, TimeUnit.SECONDS))

            val release = coordinator.releaseModelAsync("model-a")
            backend.allowLoadReturn.countDown()
            assertTrue(backend.releaseEntered.await(1, TimeUnit.SECONDS))
            assertFalse(release.isDone)

            backend.allowReleaseReturn.countDown()
            release.get(1, TimeUnit.SECONDS)
            assertFutureFailure(generation, LlmRuntimeErrorCode.CANCELLED)
            assertEquals(0, backend.generateCalls.get())
            assertEquals(1, backend.releaseCalls.get())
            assertEquals(LlmLifecycleState.Empty, coordinator.snapshot().state)
        } finally {
            backend.allowLoadReturn.countDown()
            backend.allowReleaseReturn.countDown()
            coordinator.close()
        }
    }

    @Test
    fun `close cancels active generation and completes after native free`() {
        val model = temporaryModel("close-generation")
        val backend = LifecycleRecordingBackend(
            generateEntered = CountDownLatch(1),
            allowGenerateReturn = CountDownLatch(1),
            releaseEntered = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val coordinator = coordinator(backend)

        try {
            coordinator.ensureModelReady("model-a", model.absolutePath)
            val generation = coordinator.generateTextAsync(
                modelId = "model-a",
                modelPath = model.absolutePath,
                requestId = "request-close",
                prompt = "close me",
                usedPrivateContext = false,
            )
            assertTrue(backend.generateEntered.await(1, TimeUnit.SECONDS))

            val close = coordinator.closeAsync()
            assertTrue(backend.cancelEntered.await(1, TimeUnit.SECONDS))
            assertTrue(backend.releaseEntered.await(1, TimeUnit.SECONDS))
            assertFalse(close.isDone)

            backend.allowReleaseReturn.countDown()
            close.get(1, TimeUnit.SECONDS)
            assertFutureFailure(generation, LlmRuntimeErrorCode.CANCELLED)
            assertEquals(LlmLifecycleState.Closed, coordinator.snapshot().state)
            assertTrue(coordinator.closeAsync().isDone)
        } finally {
            backend.allowGenerateReturn.countDown()
            backend.allowReleaseReturn.countDown()
        }
    }

    private fun coordinator(backend: LifecycleRecordingBackend): LlmLifecycleCoordinator {
        return LlmLifecycleCoordinator(
            packageName = "com.example.note_secret_search",
            sessionManager = LlmModelSessionManager(),
            backendFactory = object : LlmBackendFactoryContract {
                override fun create(file: File): LocalLlmBackend = backend
            },
        )
    }

    private fun temporaryModel(prefix: String): File {
        return File.createTempFile(prefix, ".gguf").apply {
            deleteOnExit()
            writeText("fixture")
        }
    }
}

private class LifecycleRecordingBackend(
    val loadEntered: CountDownLatch = CountDownLatch(0),
    val allowLoadReturn: CountDownLatch = CountDownLatch(0),
    val generateEntered: CountDownLatch = CountDownLatch(0),
    val allowGenerateReturn: CountDownLatch = CountDownLatch(0),
    val releaseEntered: CountDownLatch = CountDownLatch(0),
    val allowReleaseReturn: CountDownLatch = CountDownLatch(0),
    val cancelEntered: CountDownLatch = CountDownLatch(1),
    private val generationFailure: Throwable? = null,
) : LocalLlmBackend {
    val events: MutableList<String> = Collections.synchronizedList(mutableListOf())
    val prompts: MutableList<String> = Collections.synchronizedList(mutableListOf())
    val nativeThreadNames: MutableList<String> = Collections.synchronizedList(mutableListOf())
    val controlThreadNames: MutableList<String> = Collections.synchronizedList(mutableListOf())
    val loadCalls = AtomicInteger(0)
    val generateCalls = AtomicInteger(0)
    val releaseCalls = AtomicInteger(0)
    val cancelCalls = AtomicInteger(0)

    override fun inspect(file: File): LocalLlmInspectResult {
        return LocalLlmInspectResult(supported = true, reason = "fixture")
    }

    override fun load(modelId: String, file: File): LocalLlmBackendSession {
        recordNative("load:${file.canonicalPath}")
        loadCalls.incrementAndGet()
        loadEntered.countDown()
        assertTrue(allowLoadReturn.await(2, TimeUnit.SECONDS))
        return LocalLlmBackendSession(
            modelId = modelId,
            modelPath = file.canonicalPath,
            backendName = "fixture-backend",
            handle = loadCalls.get(),
            backend = this,
        )
    }

    override fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ): LocalLlmGenerateResult {
        recordNative("generate:${session.modelPath}")
        generateCalls.incrementAndGet()
        prompts += prompt
        generateEntered.countDown()
        assertTrue(allowGenerateReturn.await(2, TimeUnit.SECONDS))
        generationFailure?.let { throw it }
        return LocalLlmGenerateResult(
            text = "generated:$prompt",
            finishReason = "stop",
        )
    }

    override fun cancel(session: LocalLlmBackendSession) {
        controlThreadNames += Thread.currentThread().name
        cancelCalls.incrementAndGet()
        cancelEntered.countDown()
        allowGenerateReturn.countDown()
    }

    override fun release(session: LocalLlmBackendSession) {
        recordNative("release:${session.modelPath}")
        releaseCalls.incrementAndGet()
        releaseEntered.countDown()
        assertTrue(allowReleaseReturn.await(2, TimeUnit.SECONDS))
    }

    private fun recordNative(event: String) {
        events += event
        nativeThreadNames += Thread.currentThread().name
    }
}

private fun assertFutureFailure(
    future: CompletableFuture<*>,
    expectedCode: LlmRuntimeErrorCode,
): LlmRuntimeException {
    try {
        future.get(1, TimeUnit.SECONDS)
    } catch (error: ExecutionException) {
        val typed = error.cause as? LlmRuntimeException
            ?: throw AssertionError("Expected LlmRuntimeException, got ${error.cause}", error)
        assertEquals(expectedCode, typed.code)
        return typed
    }
    throw AssertionError("Expected future to fail with ${expectedCode.wireName}.")
}
