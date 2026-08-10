package com.example.note_secret_search

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.sqrt

@RunWith(AndroidJUnit4::class)
class EmbeddingRuntimeInstrumentationTest {
    private lateinit var sandbox: File

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        sandbox = File(
            context.cacheDir,
            "embedding-runtime-instrumentation-${UUID.randomUUID()}",
        ).apply { mkdirs() }
    }

    @After
    fun tearDown() {
        sandbox.deleteRecursively()
    }

    @Test
    fun tinyOnnxReturnsRealCopiedValuesAndReusesTheSession() {
        val model = TinyEmbeddingOnnxFixture.writeTo(File(sandbox, "tiny.onnx"))
        val adapter = CountingOnnxRuntimeAdapter()
        val runtime = runtime(adapter)

        runtime.ensureModelReady(MODEL_ID, model.path, modelSpec())
        runtime.ensureModelReady(MODEL_ID, model.path, modelSpec())
        val result = runtime.embedText(
            modelId = MODEL_ID,
            modelPath = model.path,
            text = "hello",
            spec = modelSpec(),
            requestId = "numeric-request",
        )
        val values = (result["values"] as List<*>)
            .map { value -> (value as Number).toDouble() }
            .toDoubleArray()

        assertArrayEquals(
            doubleArrayOf(
                2.0 / sqrt(13.0),
                3.0 / sqrt(13.0),
            ),
            values,
            1e-6,
        )
        assertEquals(3, result["tokenCount"])
        assertEquals(2, result["vectorDimension"])
        assertEquals(1, adapter.openCount)

        runtime.releaseModel(MODEL_ID)

        assertEquals(1, adapter.handles.single().closeCount)
        assertArrayEquals(
            doubleArrayOf(
                2.0 / sqrt(13.0),
                3.0 / sqrt(13.0),
            ),
            values,
            1e-6,
        )
    }

    @Test
    fun modelSwitchClosesTheOldRealSessionBeforeOpeningTheReplacement() {
        val firstModel = TinyEmbeddingOnnxFixture.writeTo(File(sandbox, "first.onnx"))
        val secondModel = TinyEmbeddingOnnxFixture.writeTo(File(sandbox, "second.onnx"))
        val adapter = CountingOnnxRuntimeAdapter()
        val runtime = runtime(adapter)

        runtime.ensureModelReady("first-model", firstModel.path, modelSpec())
        runtime.ensureModelReady("first-model", firstModel.path, modelSpec())
        runtime.ensureModelReady("second-model", secondModel.path, modelSpec())

        assertEquals(2, adapter.openCount)
        assertEquals(1, adapter.handles[0].closeCount)
        assertEquals(0, adapter.handles[1].closeCount)

        runtime.releaseModel("second-model")

        assertEquals(1, adapter.handles[1].closeCount)
    }

    @Test
    fun cancelledRequestKeepsTheReadyRealSessionReusable() {
        val model = TinyEmbeddingOnnxFixture.writeTo(File(sandbox, "cancel.onnx"))
        val adapter = CountingOnnxRuntimeAdapter()
        val runtime = runtime(adapter)
        runtime.ensureModelReady(MODEL_ID, model.path, modelSpec())
        val cancellation = CancellationHandle().apply {
            cancel(
                EmbeddingRuntimeException(
                    code = EmbeddingRuntimeErrorCode.CANCELLED,
                    stage = EmbeddingRuntimeStage.LIFECYCLE,
                    modelId = MODEL_ID,
                ),
            )
        }

        val error = assertThrows(EmbeddingRuntimeException::class.java) {
            runtime.embedText(
                modelId = MODEL_ID,
                modelPath = model.path,
                text = "hello",
                spec = modelSpec(),
                requestId = "cancelled-request",
                cancellation = cancellation,
            )
        }

        assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, error.code)
        assertEquals(0, adapter.handles.single().closeCount)

        val next = runtime.embedText(
            modelId = MODEL_ID,
            modelPath = model.path,
            text = "hello",
            spec = modelSpec(),
            requestId = "next-request",
        )

        assertEquals(1, adapter.openCount)
        assertEquals(2, next["vectorDimension"])
        runtime.releaseModel(MODEL_ID)
    }

    private fun runtime(adapter: OnnxRuntimeAdapter): OnnxEmbeddingRuntime {
        return OnnxEmbeddingRuntime(
            tokenizerLoader = EmbeddingTokenizerLoader {
                LoadedEmbeddingTokenizer(
                    tokenizer = WordpieceEmbeddingTokenizer(
                        vocab = mapOf(
                            "[PAD]" to 0,
                            "[UNK]" to 4,
                            "[CLS]" to 1,
                            "[SEP]" to 3,
                            "hello" to 2,
                        ),
                        lowercase = true,
                        maxSequenceLength = 8,
                    ),
                    contentSha256 = "sha256:${"a".repeat(64)}",
                )
            },
            sessionManager = EmbeddingModelSessionManager(),
            adapter = adapter,
            contextPackage = "instrumentation",
        )
    }

    private fun modelSpec(): OnnxEmbeddingModelSpec {
        return OnnxEmbeddingModelSpec(
            tokenizer = OnnxEmbeddingModelSpec.TokenizerSpec(
                format = "tokenizer_json",
                assetPath = "test-only/tiny-tokenizer.json",
                maxSequenceLength = 8,
                lowercase = true,
            ),
            runtime = OnnxEmbeddingModelSpec.RuntimeSpec(
                inputIdsName = "input_ids",
                attentionMaskName = "attention_mask",
                tokenTypeIdsName = "token_type_ids",
                outputName = "last_hidden_state",
                pooling = "mean",
                normalization = "l2",
            ),
        )
    }

    companion object {
        private const val MODEL_ID = "tiny-embedding-model"
    }
}

@RunWith(AndroidJUnit4::class)
class EmbeddingRuntimePluginInstrumentationTest {
    @Test
    fun blockedRuntimeLeavesMainLooperResponsiveAndCompletesOnMain() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val runtimeStarted = CountDownLatch(1)
        val allowCompletion = CountDownLatch(1)
        val heartbeat = CountDownLatch(1)
        val result = InstrumentationRecordingResult()
        val plugin = EmbeddingRuntimePlugin(
            runtime = InstrumentationEmbeddingRuntime(
                inspect = {
                    runtimeStarted.countDown()
                    allowCompletion.await(2, TimeUnit.SECONDS)
                    mapOf("status" to "ready")
                },
            ),
        )

        try {
            instrumentation.runOnMainSync {
                plugin.onMethodCall(instrumentationMethodCall("inspectModel"), result)
                Handler(Looper.getMainLooper()).post(heartbeat::countDown)
            }

            assertTrue(runtimeStarted.await(1, TimeUnit.SECONDS))
            assertTrue("Main-looper heartbeat missed 500ms gate.", heartbeat.await(500, TimeUnit.MILLISECONDS))
            assertFalse(result.successLatch.await(100, TimeUnit.MILLISECONDS))

            allowCompletion.countDown()

            assertTrue(result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals(Looper.getMainLooper().thread, result.callbackThread)
        } finally {
            allowCompletion.countDown()
            plugin.detachFromEngine()
        }
    }

    @Test
    fun runningRequestCanBeCancelledAndDetachIsPromptAndIdempotent() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val inferenceStarted = CountDownLatch(1)
        val runtimeClosed = CountDownLatch(1)
        val embedResult = InstrumentationRecordingResult()
        val cancelResult = InstrumentationRecordingResult()
        val runtime = InstrumentationEmbeddingRuntime(
            embed = { cancellation ->
                inferenceStarted.countDown()
                cancellation.awaitCancellation()
                cancellation.throwIfCancelled(MODEL_ID)
                error("unreachable")
            },
            closeRuntime = runtimeClosed::countDown,
        )
        val plugin = EmbeddingRuntimePlugin(runtime = runtime)

        instrumentation.runOnMainSync {
            plugin.onMethodCall(
                instrumentationMethodCall("embedText", "running-request"),
                embedResult,
            )
        }
        assertTrue(inferenceStarted.await(1, TimeUnit.SECONDS))

        instrumentation.runOnMainSync {
            plugin.onMethodCall(
                MethodCall(
                    "cancelRequest",
                    mapOf("requestId" to "running-request"),
                ),
                cancelResult,
            )
        }

        assertTrue(embedResult.errorLatch.await(1, TimeUnit.SECONDS))
        assertEquals("CANCELLED", embedResult.errorCode)
        assertEquals(Looper.getMainLooper().thread, embedResult.callbackThread)
        assertTrue(cancelResult.successLatch.await(1, TimeUnit.SECONDS))

        val startedAt = System.nanoTime()
        instrumentation.runOnMainSync {
            plugin.detachFromEngine()
            plugin.detachFromEngine()
        }
        val elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

        assertTrue("Detach blocked the platform thread for ${elapsedMillis}ms.", elapsedMillis < 100)
        assertTrue(runtimeClosed.await(1, TimeUnit.SECONDS))
    }

    companion object {
        private const val MODEL_ID = "instrumentation-model"
    }
}

private class CountingOnnxRuntimeAdapter(
    private val delegate: OnnxRuntimeAdapter = OrtOnnxRuntimeAdapter(),
) : OnnxRuntimeAdapter {
    val handles = mutableListOf<CountingOnnxSessionHandle>()
    var openCount = 0
        private set

    override fun openSession(
        modelPath: String,
        settings: OrtExecutionSettings,
        cancellation: CancellationHandle,
    ): OnnxSessionHandle {
        openCount += 1
        return CountingOnnxSessionHandle(
            delegate.openSession(modelPath, settings, cancellation),
        ).also(handles::add)
    }
}

private class CountingOnnxSessionHandle(
    private val delegate: OnnxSessionHandle,
) : OnnxSessionHandle {
    override val graph: ModelGraphInfo
        get() = delegate.graph

    var closeCount = 0
        private set

    override fun run(
        inputs: Map<String, IntegralTensorData>,
        outputName: String,
        cancellation: CancellationHandle,
    ): FloatTensorData {
        return delegate.run(inputs, outputName, cancellation)
    }

    override fun close() {
        if (closeCount == 0) {
            closeCount += 1
            delegate.close()
        }
    }
}

private class InstrumentationEmbeddingRuntime(
    private val inspect: () -> Map<String, Any?> = { unsupported() },
    private val embed: (CancellationHandle) -> Map<String, Any?> = { unsupported() },
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
    ): Map<String, Any?> = unsupported()

    override fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String?,
        requestId: String?,
        cancellation: CancellationHandle,
    ): Map<String, Any?> = embed(cancellation)

    override fun releaseModel(modelId: String) = Unit

    override fun releaseAll() = Unit

    override fun close() = closeRuntime()

    companion object {
        private fun unsupported(): Nothing {
            throw AssertionError("Unexpected instrumentation runtime call.")
        }
    }
}

private class InstrumentationRecordingResult : MethodChannel.Result {
    val successLatch = CountDownLatch(1)
    val errorLatch = CountDownLatch(1)
    val callbackCount = AtomicInteger(0)

    @Volatile
    var callbackThread: Thread? = null

    @Volatile
    var errorCode: String? = null

    override fun success(result: Any?) {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        successLatch.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        this.errorCode = errorCode
        errorLatch.countDown()
    }

    override fun notImplemented() {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        errorCode = "NOT_IMPLEMENTED"
        errorLatch.countDown()
    }
}

private fun instrumentationMethodCall(
    method: String,
    requestId: String = "instrumentation-request",
): MethodCall {
    val arguments = mutableMapOf<String, Any?>(
        "modelId" to "instrumentation-model",
        "modelPath" to "/test-only/model.onnx",
        "tokenizer" to mapOf(
            "format" to "tokenizer_json",
            "assetPath" to "test-only/tokenizer.json",
            "maxSequenceLength" to 8,
            "lowercase" to true,
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
    if (method == "embedText") {
        arguments["text"] = "test-only input"
        arguments["requestId"] = requestId
        arguments["verifiedChecksum"] = "sha256:${"a".repeat(64)}"
    }
    return MethodCall(method, arguments)
}
