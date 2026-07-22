package com.example.note_secret_search

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OnnxEmbeddingRuntimeTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `embed uses dynamic logical length exact output and typed inputs`() {
        val modelFile = temporaryFolder.newFile("dynamic-model.onnx")
        val session = FakeOnnxSessionHandle(
            graph = dynamicGraph(),
            output = FloatTensorData(
                shape = longArrayOf(1, 3, 2),
                values = floatArrayOf(
                    1f, 0f,
                    0f, 2f,
                    1f, 2f,
                ),
            ),
        )
        val adapter = FakeOnnxRuntimeAdapter(session)
        val runtime = runtime(adapter)

        val result = runtime.embedText(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            text = "hello",
            spec = modelSpec(),
        )

        assertEquals("last_hidden_state", session.lastOutputName)
        assertEquals(3L, session.lastInputs["input_ids"]?.shape?.get(1))
        assertEquals(IntegralTensorType.INT64, session.lastInputs["input_ids"]?.type)
        assertArrayEquals(
            longArrayOf(101, 2001, 102),
            session.lastInputs.getValue("input_ids").values,
        )
        val values = result.getValue("values") as List<*>
        assertEquals(0.4472135954999579, values[0] as Double, 1e-12)
        assertEquals(0.8944271909999159, values[1] as Double, 1e-12)
        assertEquals(3, result["tokenCount"])
        assertEquals(1, adapter.lastSettings?.interOpThreads)
        assertTrue((adapter.lastSettings?.intraOpThreads ?: 0) in 1..2)
    }

    @Test
    fun `embed pads fixed INT32 graph inputs to the declared sequence length`() {
        val modelFile = temporaryFolder.newFile("fixed-model.onnx")
        val outputValues = FloatArray(8 * 2)
        floatArrayOf(
            1f, 0f,
            0f, 2f,
            1f, 2f,
        ).copyInto(outputValues)
        val session = FakeOnnxSessionHandle(
            graph = fixedGraph(),
            output = FloatTensorData(
                shape = longArrayOf(1, 8, 2),
                values = outputValues,
            ),
        )

        val result = runtime(FakeOnnxRuntimeAdapter(session)).embedText(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            text = "hello",
            spec = modelSpec(),
        )

        val ids = session.lastInputs.getValue("input_ids")
        assertEquals(IntegralTensorType.INT32, ids.type)
        assertArrayEquals(longArrayOf(1, 8), ids.shape)
        assertArrayEquals(
            longArrayOf(101, 2001, 102, 0, 0, 0, 0, 0),
            ids.values,
        )
        assertArrayEquals(
            longArrayOf(1, 1, 1, 0, 0, 0, 0, 0),
            session.lastInputs.getValue("attention_mask").values,
        )
        val values = result.getValue("values") as List<*>
        assertEquals(0.4472135954999579, values[0] as Double, 1e-12)
        assertEquals(0.8944271909999159, values[1] as Double, 1e-12)
    }

    @Test
    fun `inspect closes temporary sessions on success and schema failure`() {
        val modelFile = temporaryFolder.newFile("inspect-model.onnx")
        val validSession = FakeOnnxSessionHandle(
            graph = dynamicGraph(),
            output = FloatTensorData(longArrayOf(1, 1, 2), floatArrayOf(1f, 1f)),
        )

        val ready = runtime(FakeOnnxRuntimeAdapter(validSession)).inspectModel(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
        )

        assertEquals("ready", ready["status"])
        assertEquals(1, validSession.closeCount)

        val invalidSession = FakeOnnxSessionHandle(
            graph = dynamicGraph().copy(outputs = emptyMap()),
            output = FloatTensorData(longArrayOf(1, 1, 2), floatArrayOf(1f, 1f)),
        )
        val degraded = runtime(FakeOnnxRuntimeAdapter(invalidSession)).inspectModel(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
        )

        assertEquals("degraded", degraded["status"])
        assertEquals(1, invalidSession.closeCount)
    }

    @Test
    fun `session load failures expose only stable typed metadata`() {
        val modelFile = temporaryFolder.newFile("private-model-path.onnx")
        val runtime = runtime(
            adapter = object : OnnxRuntimeAdapter {
                override fun openSession(
                    modelPath: String,
                    settings: OrtExecutionSettings,
                ): OnnxSessionHandle {
                    throw IllegalStateException(
                        "MODEL_PATH_SENTINEL=$modelPath TEXT_SENTINEL=secret",
                    )
                }
            },
        )

        val state = runtime.ensureModelReady(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
        )

        assertEquals("degraded", state["status"])
        assertEquals("ORT_FAILURE", state["reason"])
        assertEquals("ORT_FAILURE", state["errorCode"])
        assertEquals("session_load", state["errorStage"])
        assertFalse(state.toString().contains("MODEL_PATH_SENTINEL"))
        assertFalse(state.toString().contains("TEXT_SENTINEL"))
    }

    @Test
    fun `invalid inference output becomes typed output failure`() {
        val modelFile = temporaryFolder.newFile("invalid-output.onnx")
        val session = FakeOnnxSessionHandle(
            graph = dynamicGraph(),
            output = FloatTensorData(
                shape = longArrayOf(1, 3, 2),
                values = floatArrayOf(
                    Float.NaN, 0f,
                    0f, 2f,
                    1f, 2f,
                ),
            ),
        )

        val error = assertThrows(EmbeddingRuntimeException::class.java) {
            runtime(FakeOnnxRuntimeAdapter(session)).embedText(
                modelId = "embedding-model",
                modelPath = modelFile.absolutePath,
                text = "hello",
                spec = modelSpec(),
            )
        }

        assertEquals(EmbeddingRuntimeErrorCode.INVALID_OUTPUT, error.code)
        assertEquals(EmbeddingRuntimeStage.OUTPUT, error.stage)
        assertEquals("embedding-model", error.modelId)
        assertEquals("INVALID_OUTPUT", error.message)
    }

    @Test
    fun `tokenizer load failures become typed tokenizer state`() {
        val modelFile = temporaryFolder.newFile("tokenizer-failure.onnx")
        val runtime = runtime(
            adapter = FakeOnnxRuntimeAdapter(
                FakeOnnxSessionHandle(
                    graph = dynamicGraph(),
                    output = FloatTensorData(
                        longArrayOf(1, 1, 2),
                        floatArrayOf(1f, 1f),
                    ),
                ),
            ),
            tokenizerLoader = EmbeddingTokenizerLoader {
                throw IllegalArgumentException(
                    "TOKENIZER_SCHEMA_UNSUPPORTED: TOKEN_SENTINEL",
                )
            },
        )

        val state = runtime.ensureModelReady(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
        )

        assertEquals("TOKENIZER_SCHEMA_UNSUPPORTED", state["reason"])
        assertEquals("TOKENIZER_SCHEMA_UNSUPPORTED", state["errorCode"])
        assertEquals("tokenizer", state["errorStage"])
        assertFalse(state.toString().contains("TOKEN_SENTINEL"))
    }

    private fun dynamicGraph(): ModelGraphInfo {
        return ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to ModelTensorInfo(ModelTensorType.INT64, longArrayOf(1, -1)),
                "attention_mask" to ModelTensorInfo(ModelTensorType.INT64, longArrayOf(1, -1)),
                "token_type_ids" to ModelTensorInfo(ModelTensorType.INT64, longArrayOf(1, -1)),
            ),
            outputs = mapOf(
                "decoy" to ModelTensorInfo(ModelTensorType.FLOAT, longArrayOf(1, 1)),
                "last_hidden_state" to ModelTensorInfo(
                    ModelTensorType.FLOAT,
                    longArrayOf(1, -1, 2),
                ),
            ),
        )
    }

    private fun fixedGraph(): ModelGraphInfo {
        return ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to ModelTensorInfo(ModelTensorType.INT32, longArrayOf(1, 8)),
                "attention_mask" to ModelTensorInfo(ModelTensorType.INT32, longArrayOf(1, 8)),
                "token_type_ids" to ModelTensorInfo(ModelTensorType.INT32, longArrayOf(1, 8)),
            ),
            outputs = mapOf(
                "last_hidden_state" to ModelTensorInfo(
                    ModelTensorType.FLOAT,
                    longArrayOf(1, 8, 2),
                ),
            ),
        )
    }

    private fun runtime(
        adapter: OnnxRuntimeAdapter,
        tokenizerLoader: EmbeddingTokenizerLoader = EmbeddingTokenizerLoader {
            LoadedEmbeddingTokenizer(
                tokenizer = tokenizer(),
                contentSha256 = "sha256:${"c".repeat(64)}",
            )
        },
    ): OnnxEmbeddingRuntime {
        return OnnxEmbeddingRuntime(
            tokenizerLoader = tokenizerLoader,
            sessionManager = EmbeddingModelSessionManager(),
            adapter = adapter,
            contextPackage = "test.package",
        )
    }

    private fun tokenizer(): WordpieceEmbeddingTokenizer {
        return WordpieceEmbeddingTokenizer(
            vocab = mapOf(
                "[PAD]" to 0,
                "[UNK]" to 100,
                "[CLS]" to 101,
                "[SEP]" to 102,
                "hello" to 2001,
            ),
            lowercase = true,
            maxSequenceLength = 8,
        )
    }

    private fun modelSpec(): OnnxEmbeddingModelSpec {
        return OnnxEmbeddingModelSpec(
            tokenizer = OnnxEmbeddingModelSpec.TokenizerSpec(
                format = "tokenizer_json",
                assetPath = "unused.json",
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
}

private class FakeOnnxRuntimeAdapter(
    private val session: FakeOnnxSessionHandle,
) : OnnxRuntimeAdapter {
    var lastSettings: OrtExecutionSettings? = null

    override fun openSession(
        modelPath: String,
        settings: OrtExecutionSettings,
    ): OnnxSessionHandle {
        lastSettings = settings
        return session
    }
}

private class FakeOnnxSessionHandle(
    override val graph: ModelGraphInfo,
    private val output: FloatTensorData,
) : OnnxSessionHandle {
    var lastInputs: Map<String, IntegralTensorData> = emptyMap()
    var lastOutputName: String? = null
    var closeCount = 0

    override fun run(
        inputs: Map<String, IntegralTensorData>,
        outputName: String,
    ): FloatTensorData {
        lastInputs = inputs
        lastOutputName = outputName
        return output
    }

    override fun close() {
        closeCount += 1
    }
}
