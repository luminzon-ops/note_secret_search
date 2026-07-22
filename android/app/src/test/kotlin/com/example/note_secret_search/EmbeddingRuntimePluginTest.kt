package com.example.note_secret_search

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class EmbeddingRuntimePluginTest {
    @Test
    fun `ensure and embed require a verified checksum`() {
        val runtime = FakeEmbeddingRuntime()
        val worker = testWorker()
        val ensureResult = EmbeddingRecordingResult()
        val embedResult = EmbeddingRecordingResult()

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )

            plugin.onMethodCall(
                methodCall("ensureModelReady", includeVerifiedChecksum = false),
                ensureResult,
            )
            plugin.onMethodCall(
                methodCall("embedText", includeVerifiedChecksum = false),
                embedResult,
            )

            assertTrue(ensureResult.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("INVALID_ARGUMENT", ensureResult.errorCode)
            assertTrue(embedResult.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("INVALID_ARGUMENT", embedResult.errorCode)
        } finally {
            worker.close()
        }
    }

    @Test
    fun `inspectModel runs off the method call thread`() {
        val workerStarted = CountDownLatch(1)
        val allowCompletion = CountDownLatch(1)
        val runtime = FakeEmbeddingRuntime(
            inspect = {
                workerStarted.countDown()
                allowCompletion.await(2, TimeUnit.SECONDS)
                mapOf("status" to "ready")
            },
        )
        val worker = testWorker()
        val result = EmbeddingRecordingResult()

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )

            val startedAt = System.nanoTime()
            plugin.onMethodCall(methodCall("inspectModel"), result)
            val elapsedMillis =
                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

            assertTrue(elapsedMillis < 100)
            assertTrue(workerStarted.await(1, TimeUnit.SECONDS))
            assertNull(result.successValue)

            allowCompletion.countDown()

            assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals("ready", (result.successValue as Map<*, *>)["status"])
        } finally {
            allowCompletion.countDown()
            worker.close()
        }
    }

    @Test
    fun `ninth ordinary request fails fast with busy`() {
        val firstStarted = CountDownLatch(1)
        val allowCompletion = CountDownLatch(1)
        val runtime = FakeEmbeddingRuntime(
            inspect = {
                firstStarted.countDown()
                allowCompletion.await(2, TimeUnit.SECONDS)
                mapOf("status" to "ready")
            },
        )
        val worker = testWorker(capacity = 8)
        val results = List(9) { EmbeddingRecordingResult() }

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )

            plugin.onMethodCall(methodCall("inspectModel"), results.first())
            assertTrue(firstStarted.await(1, TimeUnit.SECONDS))
            for (index in 1 until 8) {
                plugin.onMethodCall(methodCall("inspectModel"), results[index])
            }

            val startedAt = System.nanoTime()
            plugin.onMethodCall(methodCall("inspectModel"), results[8])
            val elapsedMillis =
                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

            assertTrue(elapsedMillis < 100)
            assertTrue(results[8].errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("BUSY", results[8].errorCode)
            assertEquals("BUSY", results[8].errorMessage)
            assertEquals("queue", (results[8].errorDetails as Map<*, *>)["stage"])
            assertEquals(0, results.take(8).sumOf { it.callbackCount.get() })
        } finally {
            allowCompletion.countDown()
            worker.close()
        }
    }

    @Test
    fun `typed worker failures return sanitized stable metadata`() {
        val runtime = FakeEmbeddingRuntime(
            embed = {
                throw EmbeddingRuntimeException(
                    code = EmbeddingRuntimeErrorCode.INVALID_OUTPUT,
                    stage = EmbeddingRuntimeStage.OUTPUT,
                    modelId = "embedding-model",
                    cause = IllegalStateException(
                        "MODEL_PATH_SENTINEL TEXT_SENTINEL TOKEN_SENTINEL",
                    ),
                )
            },
        )
        val worker = testWorker()
        val result = EmbeddingRecordingResult()

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )

            plugin.onMethodCall(methodCall("embedText"), result)

            assertTrue(result.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("INVALID_OUTPUT", result.errorCode)
            assertEquals("INVALID_OUTPUT", result.errorMessage)
            assertEquals(
                mapOf("stage" to "output", "modelId" to "embedding-model"),
                result.errorDetails,
            )
            assertTrue(!result.toString().contains("SENTINEL"))
        } finally {
            worker.close()
        }
    }

    @Test
    fun `result callback completes at most once`() {
        val worker = testWorker()
        val result = EmbeddingRecordingResult()
        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = FakeEmbeddingRuntime(
                    inspect = { mapOf("status" to "ready") },
                ),
                worker = worker,
                resultDispatcher = EmbeddingDuplicatingDispatcher(),
            )

            plugin.onMethodCall(methodCall("inspectModel"), result)

            assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(1, result.callbackCount.get())
        } finally {
            worker.close()
        }
    }

    @Test
    fun `cancelRequest removes queued embedding and completes both calls once`() {
        val runningStarted = CountDownLatch(1)
        val allowRunning = CountDownLatch(1)
        val runtime = FakeEmbeddingRuntime(
            inspect = {
                runningStarted.countDown()
                allowRunning.await(2, TimeUnit.SECONDS)
                mapOf("status" to "ready")
            },
        )
        val worker = testWorker(capacity = 2)
        val runningResult = EmbeddingRecordingResult()
        val embeddingResult = EmbeddingRecordingResult()
        val cancelResult = EmbeddingRecordingResult()

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )
            plugin.onMethodCall(methodCall("inspectModel"), runningResult)
            assertTrue(runningStarted.await(1, TimeUnit.SECONDS))
            plugin.onMethodCall(
                methodCall("embedText", requestId = "queued-request"),
                embeddingResult,
            )

            plugin.onMethodCall(
                MethodCall(
                    "cancelRequest",
                    mapOf("requestId" to "queued-request"),
                ),
                cancelResult,
            )

            assertTrue(embeddingResult.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("CANCELLED", embeddingResult.errorCode)
            assertTrue(cancelResult.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(1, embeddingResult.callbackCount.get())
            assertEquals(1, cancelResult.callbackCount.get())
        } finally {
            allowRunning.countDown()
            worker.close()
        }
    }

    @Test
    fun `releaseModel cancels running inference before releasing session`() {
        val inferenceStarted = CountDownLatch(1)
        val releaseFinished = CountDownLatch(1)
        val events = mutableListOf<String>()
        val runtime = FakeEmbeddingRuntime(
            embed = { cancellation ->
                events += "embed-start"
                inferenceStarted.countDown()
                cancellation.awaitCancellation()
                cancellation.throwIfCancelled("embedding-model")
                error("unreachable")
            },
            release = {
                events += "release"
                releaseFinished.countDown()
            },
        )
        val worker = testWorker()
        val embedResult = EmbeddingRecordingResult()
        val releaseResult = EmbeddingRecordingResult()

        try {
            val plugin = EmbeddingRuntimePlugin(
                runtime = runtime,
                worker = worker,
                resultDispatcher = EmbeddingImmediateDispatcher(),
            )
            plugin.onMethodCall(
                methodCall("embedText", requestId = "running-request"),
                embedResult,
            )
            assertTrue(inferenceStarted.await(1, TimeUnit.SECONDS))

            plugin.onMethodCall(methodCall("releaseModel"), releaseResult)

            assertTrue(embedResult.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("CANCELLED", embedResult.errorCode)
            assertTrue(releaseFinished.await(1, TimeUnit.SECONDS))
            assertTrue(releaseResult.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(listOf("embed-start", "release"), events)
        } finally {
            worker.close()
        }
    }

    @Test
    fun `detach returns promptly and closes runtime on the worker`() {
        val inferenceStarted = CountDownLatch(1)
        val runtimeClosed = CountDownLatch(1)
        var closeThread: String? = null
        val runtime = FakeEmbeddingRuntime(
            embed = { cancellation ->
                inferenceStarted.countDown()
                cancellation.awaitCancellation()
                cancellation.throwIfCancelled("embedding-model")
                error("unreachable")
            },
            closeRuntime = {
                closeThread = Thread.currentThread().name
                runtimeClosed.countDown()
            },
        )
        val worker = testWorker()
        val plugin = EmbeddingRuntimePlugin(
            runtime = runtime,
            worker = worker,
            resultDispatcher = EmbeddingImmediateDispatcher(),
        )
        plugin.onMethodCall(
            methodCall("embedText", requestId = "running-request"),
            EmbeddingRecordingResult(),
        )
        assertTrue(inferenceStarted.await(1, TimeUnit.SECONDS))

        val startedAt = System.nanoTime()
        plugin.detachFromEngine()
        plugin.detachFromEngine()
        val elapsedMillis =
            TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

        assertTrue(elapsedMillis < 100)
        assertTrue(runtimeClosed.await(1, TimeUnit.SECONDS))
        assertEquals("embedding-runtime-worker", closeThread)
    }

    private fun testWorker(capacity: Int = 8): EmbeddingRuntimeWorker {
        return EmbeddingRuntimeWorker(
            capacity = capacity,
            threadPrioritySetter = {},
        )
    }

    private fun methodCall(
        method: String,
        requestId: String = "request-1",
        includeVerifiedChecksum: Boolean = true,
    ): MethodCall {
        val arguments = mutableMapOf<String, Any?>(
            "modelId" to "embedding-model",
            "modelPath" to "/private/MODEL_PATH_SENTINEL.onnx",
            "tokenizer" to mapOf(
                "format" to "tokenizer_json",
                "assetPath" to "assets/models/tokenizer.json",
                "maxSequenceLength" to 512,
                "lowercase" to false,
            ),
            "runtime" to mapOf(
                "inputIdsName" to "input_ids",
                "attentionMaskName" to "attention_mask",
                "tokenTypeIdsName" to "token_type_ids",
                "outputName" to "last_hidden_state",
                "pooling" to "mean",
                "normalization" to "l2",
            ),
        )
        if (includeVerifiedChecksum) {
            arguments["verifiedChecksum"] = "sha256:${"a".repeat(64)}"
        }
        if (method == "embedText") {
            arguments["text"] = "TEXT_SENTINEL"
            arguments["requestId"] = requestId
        }
        return MethodCall(method, arguments)
    }
}

private class FakeEmbeddingRuntime(
    private val inspect: () -> Map<String, Any?> = { unsupported() },
    private val ensure: () -> Map<String, Any?> = { unsupported() },
    private val embed: (CancellationHandle) -> Map<String, Any?> = { unsupported() },
    private val release: () -> Unit = {},
    private val closeRuntime: () -> Unit = {},
) : EmbeddingRuntimeContract {
    override fun inspectModel(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String?,
        cancellation: CancellationHandle,
    ): Map<String, Any?> = inspect()

    override fun ensureModelReady(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String?,
        cancellation: CancellationHandle,
    ): Map<String, Any?> = ensure()

    override fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String?,
        requestId: String?,
        cancellation: CancellationHandle,
    ): Map<String, Any?> = embed(cancellation)

    override fun releaseModel(modelId: String) {
        release()
    }

    override fun releaseAll() {
    }

    override fun close() {
        closeRuntime()
    }

    companion object {
        private fun unsupported(): Nothing {
            throw AssertionError("Unexpected fake embedding runtime call.")
        }
    }
}

private class EmbeddingImmediateDispatcher : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        block()
    }
}

private class EmbeddingDuplicatingDispatcher : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        block()
        block()
    }
}

private class EmbeddingRecordingResult : MethodChannel.Result {
    val successLatch = CountDownLatch(1)
    val errorLatch = CountDownLatch(1)
    val callbackCount = AtomicInteger(0)

    @Volatile
    var successValue: Any? = null

    @Volatile
    var errorCode: String? = null

    @Volatile
    var errorMessage: String? = null

    @Volatile
    var errorDetails: Any? = null

    override fun success(result: Any?) {
        callbackCount.incrementAndGet()
        successValue = result
        successLatch.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        callbackCount.incrementAndGet()
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
        errorLatch.countDown()
    }

    override fun notImplemented() {
        callbackCount.incrementAndGet()
        errorCode = "NOT_IMPLEMENTED"
        errorLatch.countDown()
    }

    override fun toString(): String {
        return "EmbeddingRecordingResult(" +
            "successValue=$successValue, " +
            "errorCode=$errorCode, " +
            "errorMessage=$errorMessage, " +
            "errorDetails=$errorDetails)"
    }
}
