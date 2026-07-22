package com.example.note_secret_search

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.sqrt

@RunWith(AndroidJUnit4::class)
class BgeEmbeddingRuntimeInstrumentationTest {
    @Test
    fun pinnedBgeMatchesIndependentChineseReferenceAndReusesSession() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = requiredBgeModel()
        val reference = loadReference()
        val adapter = BgeCountingOnnxRuntimeAdapter()
        val runtime = bgeRuntime(context, adapter)

        try {
            val firstReady = runtime.ensureModelReady(
                modelId = MODEL_ID,
                modelPath = model.path,
                spec = bgeModelSpec(),
                verifiedChecksum = BGE_CHECKSUM,
            )
            val secondReady = runtime.ensureModelReady(
                modelId = MODEL_ID,
                modelPath = model.path,
                spec = bgeModelSpec(),
                verifiedChecksum = BGE_CHECKSUM,
            )
            val first = embeddingVector(
                runtime.embedText(
                    modelId = MODEL_ID,
                    modelPath = model.path,
                    text = reference.text,
                    spec = bgeModelSpec(),
                    verifiedChecksum = BGE_CHECKSUM,
                    requestId = "bge-reference-1",
                ),
            )
            val second = embeddingVector(
                runtime.embedText(
                    modelId = MODEL_ID,
                    modelPath = model.path,
                    text = reference.text,
                    spec = bgeModelSpec(),
                    verifiedChecksum = BGE_CHECKSUM,
                    requestId = "bge-reference-2",
                ),
            )

            assertEquals("ready", firstReady["status"])
            assertEquals("ready", secondReady["status"])
            assertEquals(BGE_VECTOR_DIMENSION, firstReady["vectorDimension"])
            assertEquals(1, adapter.openCount)
            assertNormalizedVector(first)
            assertTrue(
                "Independent BGE reference cosine was ${cosine(first, reference.values)}.",
                cosine(first, reference.values) >= REFERENCE_MIN_COSINE,
            )
            assertTrue(
                "Independent BGE component delta was ${maxAbsoluteDelta(first, reference.values)}.",
                maxAbsoluteDelta(first, reference.values) <= REFERENCE_MAX_ABSOLUTE_DELTA,
            )
            assertTrue(
                "Repeated BGE inference cosine was ${cosine(first, second)}.",
                cosine(first, second) >= REPEATED_MIN_COSINE,
            )
        } finally {
            runtime.close()
        }

        assertEquals(1, adapter.handles.single().closeCount)
    }

    @Test
    fun pinnedBgeSurvivesSwitchCancellationLongRunAndRuntimeRecreate() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = requiredBgeModel()
        val runEntered = CountDownLatch(1)
        val adapter = BgeCountingOnnxRuntimeAdapter(onFirstRunEntered = runEntered::countDown)
        val runtime = bgeRuntime(context, adapter)
        val cancellation = CancellationHandle()
        val executor = Executors.newSingleThreadExecutor()

        try {
            runtime.ensureModelReady(
                modelId = "bge-before-switch",
                modelPath = model.path,
                spec = bgeModelSpec(),
                verifiedChecksum = BGE_CHECKSUM,
            )
            runtime.ensureModelReady(
                modelId = "bge-after-switch",
                modelPath = model.path,
                spec = bgeModelSpec(),
                verifiedChecksum = BGE_CHECKSUM,
            )

            assertEquals(2, adapter.openCount)
            assertEquals(1, adapter.handles[0].closeCount)

            val cancelled = executor.submit<Map<String, Any?>> {
                runtime.embedText(
                    modelId = "bge-after-switch",
                    modelPath = model.path,
                    text = LONG_TEXT,
                    spec = bgeModelSpec(),
                    verifiedChecksum = BGE_CHECKSUM,
                    requestId = "bge-running-cancel",
                    cancellation = cancellation,
                )
            }
            assertTrue("BGE inference did not reach the real session.", runEntered.await(30, TimeUnit.SECONDS))
            cancellation.cancel(
                EmbeddingRuntimeException(
                    code = EmbeddingRuntimeErrorCode.CANCELLED,
                    stage = EmbeddingRuntimeStage.LIFECYCLE,
                    modelId = "bge-after-switch",
                ),
            )
            val cancelledError = assertThrows(ExecutionException::class.java) {
                cancelled.get(30, TimeUnit.SECONDS)
            }.cause as EmbeddingRuntimeException

            assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, cancelledError.code)
            assertEquals(0, adapter.handles[1].closeCount)

            repeat(LONG_RUN_EMBEDDING_COUNT) { index ->
                val result = runtime.embedText(
                    modelId = "bge-after-switch",
                    modelPath = model.path,
                    text = LONG_RUN_CORPUS[index % LONG_RUN_CORPUS.size] + " $index",
                    spec = bgeModelSpec(),
                    verifiedChecksum = BGE_CHECKSUM,
                    requestId = "bge-long-run-$index",
                )
                assertNormalizedVector(embeddingVector(result))
            }

            assertEquals(2, adapter.openCount)
        } finally {
            executor.shutdownNow()
            runtime.close()
        }

        assertEquals(1, adapter.handles[1].closeCount)

        val recreatedAdapter = BgeCountingOnnxRuntimeAdapter()
        val recreated = bgeRuntime(context, recreatedAdapter)
        try {
            val vector = embeddingVector(
                recreated.embedText(
                    modelId = "bge-recreated",
                    modelPath = model.path,
                    text = "引擎重建后的中文检索",
                    spec = bgeModelSpec(),
                    verifiedChecksum = BGE_CHECKSUM,
                    requestId = "bge-recreated-request",
                ),
            )
            assertNormalizedVector(vector)
            assertEquals(1, recreatedAdapter.openCount)
        } finally {
            recreated.close()
        }
        assertEquals(1, recreatedAdapter.handles.single().closeCount)
    }

    @Test
    fun realBgeWorkerKeepsMainLooperResponsiveAndCompletesOnMain() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val model = requiredBgeModel()
        val result = BgeRecordingResult()
        val heartbeat = CountDownLatch(1)
        val plugin = EmbeddingRuntimePlugin(
            runtime = bgeRuntime(
                instrumentation.targetContext,
                BgeCountingOnnxRuntimeAdapter(),
            ),
        )

        try {
            instrumentation.runOnMainSync {
                plugin.onMethodCall(bgeEmbedMethodCall(model), result)
                Handler(Looper.getMainLooper()).post(heartbeat::countDown)
            }

            assertTrue(
                "Main-looper heartbeat missed the 500ms real-BGE gate.",
                heartbeat.await(500, TimeUnit.MILLISECONDS),
            )
            assertTrue(
                "Real BGE worker did not complete within 120 seconds.",
                result.completion.await(120, TimeUnit.SECONDS),
            )
            assertEquals(1, result.callbackCount.get())
            assertEquals(null, result.errorCode)
            assertEquals(Looper.getMainLooper().thread, result.callbackThread)
            assertNormalizedVector(embeddingVector(requireNotNull(result.value)))
        } finally {
            instrumentation.runOnMainSync(plugin::detachFromEngine)
        }
    }

    private fun requiredBgeModel(): File {
        val path = InstrumentationRegistry.getArguments().getString(BGE_MODEL_PATH_ARGUMENT)
        assertFalse(
            "Pass -e $BGE_MODEL_PATH_ARGUMENT with the pinned BGE model path.",
            path.isNullOrBlank(),
        )
        val model = File(requireNotNull(path))
        assertTrue("Pinned BGE model is missing on the device.", model.isFile)
        assertTrue("Pinned BGE model is not readable on the device.", model.canRead())
        return model
    }

    private fun loadReference(): BgeReference {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val raw = instrumentation.context.assets.open(BGE_REFERENCE_ASSET)
            .bufferedReader()
            .use { it.readText() }
        val json = JSONObject(raw)
        assertEquals(BGE_CHECKSUM, json.getString("modelChecksum"))
        val values = json.getJSONArray("values")
        return BgeReference(
            text = json.getString("text"),
            values = DoubleArray(values.length()) { index -> values.getDouble(index) },
        )
    }

    companion object {
        const val BGE_MODEL_PATH_ARGUMENT = "bgeModelPath"
        const val BGE_CHECKSUM =
            "sha256:69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a"

        private const val MODEL_ID = "bge-small-zh-v1.5-device-gate"
        private const val BGE_REFERENCE_ASSET = "bge_small_zh_v1_5_reference.json"
        private const val BGE_VECTOR_DIMENSION = 512
        private const val LONG_RUN_EMBEDDING_COUNT = 52
        private const val REFERENCE_MIN_COSINE = 0.99999
        private const val REFERENCE_MAX_ABSOLUTE_DELTA = 0.0001
        private const val REPEATED_MIN_COSINE = 0.999999
        private val LONG_TEXT = "中文搜索与本地语义索引。".repeat(64)
        private val LONG_RUN_CORPUS = listOf(
            "中文密码条目搜索",
            "离线笔记语义检索",
            "本地模型隐私保护",
            "长文本索引取消恢复",
        )
    }
}

private data class BgeReference(
    val text: String,
    val values: DoubleArray,
)

private fun bgeRuntime(
    context: Context,
    adapter: OnnxRuntimeAdapter,
): OnnxEmbeddingRuntime {
    return OnnxEmbeddingRuntime(
        tokenizerLoader = EmbeddingTokenizerLoader { spec ->
            val raw = context.assets.open("flutter_assets/${spec.assetPath}").use { it.readBytes() }
            LoadedEmbeddingTokenizer(
                tokenizer = WordpieceEmbeddingTokenizer(
                    definition = TokenizerJsonParser.parse(
                        rawJson = raw.toString(Charsets.UTF_8),
                        expectedLowercase = spec.lowercase,
                    ),
                    maxSequenceLength = spec.maxSequenceLength,
                ),
                contentSha256 = sha256String(raw),
            )
        },
        sessionManager = EmbeddingModelSessionManager(),
        adapter = adapter,
        contextPackage = context.packageName,
    )
}

internal fun bgeModelSpec(): OnnxEmbeddingModelSpec {
    return OnnxEmbeddingModelSpec(
        tokenizer = OnnxEmbeddingModelSpec.TokenizerSpec(
            format = "tokenizer_json",
            assetPath = "assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json",
            maxSequenceLength = 256,
            lowercase = false,
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

internal fun embeddingVector(result: Map<String, Any?>): DoubleArray {
    val values = result["values"] as? List<*>
    assertNotNull("Embedding result did not contain values.", values)
    return requireNotNull(values).map { value -> (value as Number).toDouble() }.toDoubleArray()
}

private fun assertNormalizedVector(vector: DoubleArray) {
    assertEquals(512, vector.size)
    assertTrue("Embedding vector contains a non-finite value.", vector.all(Double::isFinite))
    assertEquals(1.0, sqrt(vector.sumOf { value -> value * value }), 1e-5)
}

private fun cosine(first: DoubleArray, second: DoubleArray): Double {
    require(first.size == second.size)
    var dot = 0.0
    var firstNorm = 0.0
    var secondNorm = 0.0
    first.indices.forEach { index ->
        dot += first[index] * second[index]
        firstNorm += first[index] * first[index]
        secondNorm += second[index] * second[index]
    }
    return dot / sqrt(firstNorm * secondNorm)
}

private fun maxAbsoluteDelta(first: DoubleArray, second: DoubleArray): Double {
    require(first.size == second.size)
    return first.indices.maxOf { index -> abs(first[index] - second[index]) }
}

private class BgeCountingOnnxRuntimeAdapter(
    private val delegate: OnnxRuntimeAdapter = OrtOnnxRuntimeAdapter(),
    private val onFirstRunEntered: (() -> Unit)? = null,
) : OnnxRuntimeAdapter {
    val handles = mutableListOf<BgeCountingOnnxSessionHandle>()
    var openCount = 0
        private set
    private val firstRunSignalled = AtomicBoolean(false)

    override fun openSession(
        modelPath: String,
        settings: OrtExecutionSettings,
        cancellation: CancellationHandle,
    ): OnnxSessionHandle {
        openCount += 1
        return BgeCountingOnnxSessionHandle(
            delegate = delegate.openSession(modelPath, settings, cancellation),
            onRunEntered = {
                if (firstRunSignalled.compareAndSet(false, true)) {
                    onFirstRunEntered?.invoke()
                }
            },
        ).also(handles::add)
    }
}

private class BgeCountingOnnxSessionHandle(
    private val delegate: OnnxSessionHandle,
    private val onRunEntered: () -> Unit,
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
        onRunEntered()
        return delegate.run(inputs, outputName, cancellation)
    }

    override fun close() {
        if (closeCount == 0) {
            closeCount += 1
            delegate.close()
        }
    }
}

private class BgeRecordingResult : MethodChannel.Result {
    val completion = CountDownLatch(1)
    val callbackCount = AtomicInteger(0)

    @Volatile
    var callbackThread: Thread? = null

    @Volatile
    var errorCode: String? = null

    @Volatile
    var value: Map<String, Any?>? = null

    override fun success(result: Any?) {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        @Suppress("UNCHECKED_CAST")
        value = result as? Map<String, Any?>
        completion.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        this.errorCode = errorCode
        completion.countDown()
    }

    override fun notImplemented() {
        callbackCount.incrementAndGet()
        callbackThread = Thread.currentThread()
        errorCode = "NOT_IMPLEMENTED"
        completion.countDown()
    }
}

private fun bgeEmbedMethodCall(model: File): MethodCall {
    return MethodCall(
        "embedText",
        mapOf(
            "modelId" to "bge-worker-device-gate",
            "modelPath" to model.path,
            "text" to "真实 BGE worker 不应阻塞 Android 主线程。",
            "verifiedChecksum" to BgeEmbeddingRuntimeInstrumentationTest.BGE_CHECKSUM,
            "requestId" to "bge-worker-request",
            "tokenizer" to mapOf(
                "format" to "tokenizer_json",
                "assetPath" to "assets/model_catalog/tokenizers/bge_small_zh_v1_5_tokenizer.json",
                "maxSequenceLength" to 256,
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
        ),
    )
}
