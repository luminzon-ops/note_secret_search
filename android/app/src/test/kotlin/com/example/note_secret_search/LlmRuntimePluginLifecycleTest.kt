package com.example.note_secret_search

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class LlmRuntimePluginLifecycleTest {
    @Test
    fun `generate forwards explicit request id and returns backend provenance`() {
        val runtime = PluginLifecycleRuntime()
        val executor = Executors.newFixedThreadPool(2)
        val result = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            workerExecutor = executor,
            resultDispatcher = ImmediatePluginResultDispatcher(),
        )

        try {
            plugin.onMethodCall(
                MethodCall(
                    "generateText",
                    mapOf(
                        "modelId" to "model-a",
                        "modelPath" to "/models/model.gguf",
                        "requestId" to "request-7",
                        "prompt" to "hello",
                    ),
                ),
                result,
            )

            assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals("request-7", runtime.lastRequestId)
            val payload = result.successValue as Map<*, *>
            assertEquals("request-7", payload["requestId"])
            assertEquals("fixture-backend", payload["actualBackend"])
            assertEquals("model-a", payload["actualModel"])
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `cancelGeneration is idempotent at the method channel boundary`() {
        val runtime = PluginLifecycleRuntime()
        val result = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            resultDispatcher = ImmediatePluginResultDispatcher(),
        )

        plugin.onMethodCall(
            MethodCall(
                "cancelGeneration",
                mapOf("requestId" to "request-7"),
            ),
            result,
        )

        assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
        assertEquals(1, runtime.cancelCalls.get())
        assertEquals(1, result.callbackCount.get())
    }

    @Test
    fun `cancel reaches runtime while generation call is still blocking a worker`() {
        val runtime = PluginLifecycleRuntime(
            generationStarted = CountDownLatch(1),
            allowGenerationReturn = CountDownLatch(1),
            cancelUnblocksGeneration = true,
        )
        val generationResult = PluginRecordingResult()
        val cancelResult = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            resultDispatcher = ImmediatePluginResultDispatcher(),
        )

        try {
            plugin.onMethodCall(
                MethodCall(
                    "generateText",
                    mapOf(
                        "modelId" to "model-a",
                        "modelPath" to "/models/model.gguf",
                        "requestId" to "request-blocked",
                        "prompt" to "hello",
                    ),
                ),
                generationResult,
            )
            assertTrue(runtime.generationStarted.await(1, TimeUnit.SECONDS))

            plugin.onMethodCall(
                MethodCall(
                    "cancelGeneration",
                    mapOf("requestId" to "request-blocked"),
                ),
                cancelResult,
            )

            assertTrue(cancelResult.successLatch.await(1, TimeUnit.SECONDS))
            assertTrue(generationResult.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(1, runtime.cancelCalls.get())
        } finally {
            runtime.allowGenerationReturn.countDown()
            plugin.detachFromEngine().get(1, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `release callback waits for runtime acknowledgement`() {
        val runtime = PluginLifecycleRuntime(
            releaseStarted = CountDownLatch(1),
            allowReleaseReturn = CountDownLatch(1),
        )
        val executor = Executors.newSingleThreadExecutor()
        val result = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            workerExecutor = executor,
            resultDispatcher = ImmediatePluginResultDispatcher(),
        )

        try {
            plugin.onMethodCall(
                MethodCall(
                    "releaseModel",
                    mapOf("modelId" to "model-a"),
                ),
                result,
            )
            assertTrue(runtime.releaseStarted.await(1, TimeUnit.SECONDS))
            assertEquals(0, result.callbackCount.get())

            runtime.allowReleaseReturn.countDown()
            assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(1, runtime.releaseCalls.get())
        } finally {
            runtime.allowReleaseReturn.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `detach suppresses late runtime callback and closes runtime`() {
        val runtime = PluginLifecycleRuntime(
            generationStarted = CountDownLatch(1),
            allowGenerationReturn = CountDownLatch(1),
        )
        val executor = Executors.newSingleThreadExecutor()
        val result = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            workerExecutor = executor,
            resultDispatcher = ImmediatePluginResultDispatcher(),
        )

        try {
            plugin.onMethodCall(
                MethodCall(
                    "generateText",
                    mapOf(
                        "modelId" to "model-a",
                        "modelPath" to "/models/model.gguf",
                        "requestId" to "request-late",
                        "prompt" to "hello",
                    ),
                ),
                result,
            )
            assertTrue(runtime.generationStarted.await(1, TimeUnit.SECONDS))

            val detached = plugin.detachFromEngine()
            assertTrue(runtime.closeCalled)
            detached.get(1, TimeUnit.SECONDS)
            runtime.allowGenerationReturn.countDown()
            Thread.sleep(50)

            assertEquals(0, result.callbackCount.get())
        } finally {
            runtime.allowGenerationReturn.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `method completion remains one shot when dispatcher invokes callback twice`() {
        val runtime = PluginLifecycleRuntime()
        val result = PluginRecordingResult()
        val plugin = LlmRuntimePlugin(
            runtime = runtime,
            resultDispatcher = DoubleDispatchPluginResultDispatcher(),
        )

        plugin.onMethodCall(
            MethodCall(
                "inspectModel",
                mapOf(
                    "modelId" to "model-a",
                    "modelPath" to "/models/model.gguf",
                ),
            ),
            result,
        )

        assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
        assertEquals(1, result.callbackCount.get())
    }
}

private class PluginLifecycleRuntime(
    val generationStarted: CountDownLatch = CountDownLatch(0),
    val allowGenerationReturn: CountDownLatch = CountDownLatch(0),
    val releaseStarted: CountDownLatch = CountDownLatch(0),
    val allowReleaseReturn: CountDownLatch = CountDownLatch(0),
    private val cancelUnblocksGeneration: Boolean = false,
) : LocalLlmRuntimeContract {
    var lastRequestId: String? = null
    val cancelCalls = AtomicInteger(0)
    val releaseCalls = AtomicInteger(0)
    var closeCalled = false

    override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
        return mapOf("status" to "installed_unverified", "ready" to false)
    }

    override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
        return mapOf("status" to "ready", "ready" to true)
    }

    override fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
    ): Map<String, Any?> {
        return mapOf("status" to "ready", "text" to "legacy")
    }

    override fun generateText(
        modelId: String,
        modelPath: String,
        requestId: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        lastRequestId = requestId
        generationStarted.countDown()
        allowGenerationReturn.await(2, TimeUnit.SECONDS)
        return mapOf(
            "status" to "ready",
            "text" to "fixture",
            "requestId" to requestId,
            "actualBackend" to "fixture-backend",
            "actualModel" to modelId,
        )
    }

    override fun cancelGeneration(requestId: String): Boolean {
        cancelCalls.incrementAndGet()
        if (cancelUnblocksGeneration) {
            allowGenerationReturn.countDown()
        }
        return true
    }

    override fun releaseModel(modelId: String) {
        releaseCalls.incrementAndGet()
        releaseStarted.countDown()
        allowReleaseReturn.await(2, TimeUnit.SECONDS)
    }

    override fun closeAsync(): CompletableFuture<Unit> {
        closeCalled = true
        return CompletableFuture.completedFuture(Unit)
    }
}

private class ImmediatePluginResultDispatcher : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        block()
    }
}

private class DoubleDispatchPluginResultDispatcher : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        block()
        block()
    }
}

private class PluginRecordingResult : MethodChannel.Result {
    val successLatch = CountDownLatch(1)
    val callbackCount = AtomicInteger(0)
    var successValue: Any? = null

    override fun success(result: Any?) {
        callbackCount.incrementAndGet()
        successValue = result
        successLatch.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        callbackCount.incrementAndGet()
        successLatch.countDown()
    }

    override fun notImplemented() {
        callbackCount.incrementAndGet()
        successLatch.countDown()
    }
}
