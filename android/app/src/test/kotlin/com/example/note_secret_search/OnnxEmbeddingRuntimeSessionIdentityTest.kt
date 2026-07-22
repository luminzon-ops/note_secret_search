package com.example.note_secret_search

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OnnxEmbeddingRuntimeSessionIdentityTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `same identity reuses verified model tokenizer contract and session`() {
        val modelFile = temporaryFolder.newFile("model.onnx")
        val fixture = RuntimeIdentityFixture()

        fixture.runtime.ensureModelReady(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
            verifiedChecksum = CHECKSUM_A,
        )
        fixture.runtime.ensureModelReady(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            spec = modelSpec(),
            verifiedChecksum = CHECKSUM_A,
        )
        fixture.runtime.embedText(
            modelId = "embedding-model",
            modelPath = modelFile.absolutePath,
            text = "hello",
            spec = modelSpec(),
            verifiedChecksum = CHECKSUM_A,
            requestId = "request-1",
        )

        assertEquals(1, fixture.checksumVerifier.verifyCount)
        assertEquals(1, fixture.tokenizerLoader.loadCount)
        assertEquals(1, fixture.adapter.openCount)
        assertEquals(0, fixture.adapter.sessions.single().closeCount)
    }

    @Test
    fun `every session identity field change closes and rebuilds the session`() {
        val firstModel = temporaryFolder.newFile("first.onnx")
        val secondModel = temporaryFolder.newFile("second.onnx")
        val fixture = RuntimeIdentityFixture()
        val requests = listOf(
            IdentityRequest(
                modelId = "model-a",
                path = firstModel.absolutePath,
                checksum = CHECKSUM_A,
                spec = modelSpec(),
            ),
            IdentityRequest(
                modelId = "model-b",
                path = firstModel.absolutePath,
                checksum = CHECKSUM_A,
                spec = modelSpec(),
            ),
            IdentityRequest(
                modelId = "model-b",
                path = secondModel.absolutePath,
                checksum = CHECKSUM_A,
                spec = modelSpec(),
            ),
            IdentityRequest(
                modelId = "model-b",
                path = secondModel.absolutePath,
                checksum = CHECKSUM_B,
                spec = modelSpec(),
            ),
            IdentityRequest(
                modelId = "model-b",
                path = secondModel.absolutePath,
                checksum = CHECKSUM_B,
                spec = modelSpec(
                    tokenizer = tokenizerSpec(maxSequenceLength = 16),
                ),
            ),
            IdentityRequest(
                modelId = "model-b",
                path = secondModel.absolutePath,
                checksum = CHECKSUM_B,
                spec = modelSpec(
                    tokenizer = tokenizerSpec(maxSequenceLength = 16),
                    runtime = runtimeSpec(pooling = "cls"),
                ),
            ),
        )

        requests.forEach { request ->
            fixture.runtime.ensureModelReady(
                modelId = request.modelId,
                modelPath = request.path,
                spec = request.spec,
                verifiedChecksum = request.checksum,
            )
        }

        assertEquals(requests.size, fixture.adapter.openCount)
        assertEquals(requests.size - 1, fixture.adapter.totalCloseCount)
        assertEquals(0, fixture.adapter.sessions.last().closeCount)
    }

    @Test
    fun `failed replacement leaves no stale session for later inference`() {
        val firstModel = temporaryFolder.newFile("first.onnx")
        val secondModel = temporaryFolder.newFile("second.onnx")
        val fixture = RuntimeIdentityFixture()

        fixture.runtime.ensureModelReady(
            modelId = "model-a",
            modelPath = firstModel.absolutePath,
            spec = modelSpec(),
            verifiedChecksum = CHECKSUM_A,
        )
        fixture.checksumVerifier.failure = EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.CHECKSUM_MISMATCH,
            stage = EmbeddingRuntimeStage.CHECKSUM,
            modelId = "model-b",
        )

        val state = fixture.runtime.ensureModelReady(
            modelId = "model-b",
            modelPath = secondModel.absolutePath,
            spec = modelSpec(),
            verifiedChecksum = CHECKSUM_B,
        )

        assertEquals("CHECKSUM_MISMATCH", state["errorCode"])
        assertEquals(1, fixture.adapter.sessions.single().closeCount)

        fixture.checksumVerifier.failure = null
        fixture.adapter.openFailure = IllegalStateException("load failure sentinel")
        assertThrows(EmbeddingRuntimeException::class.java) {
            fixture.runtime.embedText(
                modelId = "model-b",
                modelPath = secondModel.absolutePath,
                text = "hello",
                spec = modelSpec(),
                verifiedChecksum = CHECKSUM_B,
                requestId = "request-2",
            )
        }
        assertEquals(3, fixture.checksumVerifier.verifyCount)
        assertEquals(1, fixture.tokenizerLoader.loadCount)
        assertEquals(1, fixture.adapter.openCount)
    }

    private data class IdentityRequest(
        val modelId: String,
        val path: String,
        val checksum: String,
        val spec: OnnxEmbeddingModelSpec,
    )

    private class RuntimeIdentityFixture {
        val checksumVerifier = CountingChecksumVerifier()
        val tokenizerLoader = CountingTokenizerLoader()
        val adapter = RecordingRuntimeAdapter()
        val runtime = OnnxEmbeddingRuntime(
            tokenizerLoader = tokenizerLoader,
            sessionManager = EmbeddingModelSessionManager(),
            adapter = adapter,
            contextPackage = "test.package",
            checksumVerifier = checksumVerifier,
            executionSettings = OrtExecutionSettings(
                interOpThreads = 1,
                intraOpThreads = 2,
                strategyVersion = 1,
            ),
        )
    }

    private class CountingChecksumVerifier : EmbeddingModelChecksumVerifier {
        var verifyCount = 0
        var failure: EmbeddingRuntimeException? = null

        override fun verify(
            file: File,
            expectedChecksum: String?,
            modelId: String,
        ): String {
            verifyCount += 1
            failure?.let { throw it }
            return requireNotNull(expectedChecksum)
        }
    }

    private class CountingTokenizerLoader : EmbeddingTokenizerLoader {
        var loadCount = 0

        override fun load(
            spec: OnnxEmbeddingModelSpec.TokenizerSpec,
        ): LoadedEmbeddingTokenizer {
            loadCount += 1
            return LoadedEmbeddingTokenizer(
                tokenizer = WordpieceEmbeddingTokenizer(
                    vocab = mapOf(
                        "[PAD]" to 0,
                        "[UNK]" to 100,
                        "[CLS]" to 101,
                        "[SEP]" to 102,
                        "hello" to 2001,
                    ),
                    lowercase = spec.lowercase,
                    maxSequenceLength = spec.maxSequenceLength,
                ),
                contentSha256 = "sha256:${loadCount.toString(16).padStart(64, '0')}",
            )
        }
    }

    private class RecordingRuntimeAdapter : OnnxRuntimeAdapter {
        val sessions = mutableListOf<RecordingSession>()
        var openFailure: Throwable? = null

        val openCount: Int
            get() = sessions.size

        val totalCloseCount: Int
            get() = sessions.sumOf(RecordingSession::closeCount)

        override fun openSession(
            modelPath: String,
            settings: OrtExecutionSettings,
        ): OnnxSessionHandle {
            openFailure?.let { throw it }
            return RecordingSession().also(sessions::add)
        }
    }

    private class RecordingSession : OnnxSessionHandle {
        override val graph = dynamicGraph()
        var closeCount = 0

        override fun run(
            inputs: Map<String, IntegralTensorData>,
            outputName: String,
        ): FloatTensorData {
            return FloatTensorData(
                shape = longArrayOf(1, 3, 2),
                values = floatArrayOf(
                    1f, 0f,
                    0f, 1f,
                    1f, 1f,
                ),
            )
        }

        override fun close() {
            closeCount += 1
        }
    }

    companion object {
        private const val CHECKSUM_A =
            "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        private const val CHECKSUM_B =
            "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        private fun tokenizerSpec(
            maxSequenceLength: Int = 8,
        ) = OnnxEmbeddingModelSpec.TokenizerSpec(
            format = "tokenizer_json",
            assetPath = "unused.json",
            maxSequenceLength = maxSequenceLength,
            lowercase = true,
        )

        private fun runtimeSpec(
            pooling: String = "mean",
        ) = OnnxEmbeddingModelSpec.RuntimeSpec(
            inputIdsName = "input_ids",
            attentionMaskName = "attention_mask",
            tokenTypeIdsName = "token_type_ids",
            outputName = "last_hidden_state",
            pooling = pooling,
            normalization = "l2",
        )

        private fun modelSpec(
            tokenizer: OnnxEmbeddingModelSpec.TokenizerSpec = tokenizerSpec(),
            runtime: OnnxEmbeddingModelSpec.RuntimeSpec = runtimeSpec(),
        ) = OnnxEmbeddingModelSpec(
            tokenizer = tokenizer,
            runtime = runtime,
        )

        private fun dynamicGraph() = ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to ModelTensorInfo(
                    ModelTensorType.INT64,
                    longArrayOf(1, -1),
                ),
                "attention_mask" to ModelTensorInfo(
                    ModelTensorType.INT64,
                    longArrayOf(1, -1),
                ),
                "token_type_ids" to ModelTensorInfo(
                    ModelTensorType.INT64,
                    longArrayOf(1, -1),
                ),
            ),
            outputs = mapOf(
                "last_hidden_state" to ModelTensorInfo(
                    ModelTensorType.FLOAT,
                    longArrayOf(1, -1, 2),
                ),
            ),
        )
    }
}
