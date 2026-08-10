package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddingModelSessionManagerTest {
    @Test
    fun `same identity reuses tokenizer contract and session`() {
        val manager = EmbeddingModelSessionManager()
        val identity = identity()
        val handle = SessionManagerFakeHandle()
        var loadCount = 0

        val first = manager.getOrLoad(identity) {
            loadCount += 1
            prepared(identity, handle)
        }
        val second = manager.getOrLoad(identity) {
            loadCount += 1
            prepared(identity, SessionManagerFakeHandle())
        }

        assertSame(first, second)
        assertSame(first.tokenizer, second.tokenizer)
        assertSame(first.contract, second.contract)
        assertEquals(1, loadCount)
        assertEquals(0, handle.closeCount)
        assertEquals(SessionSlotState.Ready(identity), manager.state)
    }

    @Test
    fun `identity change closes old session before loading replacement`() {
        val manager = EmbeddingModelSessionManager()
        val firstIdentity = identity(modelPath = "C:/models/first.onnx")
        val secondIdentity = identity(modelPath = "C:/models/second.onnx")
        val events = mutableListOf<String>()
        val firstHandle = SessionManagerFakeHandle(onClose = { events += "close-first" })
        val secondHandle = SessionManagerFakeHandle()

        manager.getOrLoad(firstIdentity) {
            prepared(firstIdentity, firstHandle)
        }
        manager.getOrLoad(secondIdentity) {
            events += "load-second"
            prepared(secondIdentity, secondHandle)
        }

        assertEquals(listOf("close-first", "load-second"), events)
        assertEquals(1, firstHandle.closeCount)
        assertEquals(0, secondHandle.closeCount)
        assertEquals(SessionSlotState.Ready(secondIdentity), manager.state)
    }

    @Test
    fun `replacement load failure leaves empty slot without stale session`() {
        val manager = EmbeddingModelSessionManager()
        val firstIdentity = identity()
        val replacementIdentity = identity(verifiedSha256 = "sha256:${"b".repeat(64)}")
        val firstHandle = SessionManagerFakeHandle()
        manager.getOrLoad(firstIdentity) {
            prepared(firstIdentity, firstHandle)
        }

        assertThrows(IllegalStateException::class.java) {
            manager.getOrLoad(replacementIdentity) {
                throw IllegalStateException("load failure")
            }
        }

        assertEquals(1, firstHandle.closeCount)
        assertEquals(SessionSlotState.Empty, manager.state)
        assertEquals(null, manager.get(replacementIdentity))
    }

    @Test
    fun `mismatched prepared identity closes partial session and clears slot`() {
        val manager = EmbeddingModelSessionManager()
        val requestedIdentity = identity()
        val returnedIdentity = identity(
            verifiedSha256 = "sha256:${"b".repeat(64)}",
        )
        val handle = SessionManagerFakeHandle()

        assertThrows(IllegalArgumentException::class.java) {
            manager.getOrLoad(requestedIdentity) {
                prepared(returnedIdentity, handle)
            }
        }

        assertEquals(1, handle.closeCount)
        assertEquals(SessionSlotState.Empty, manager.state)
        assertEquals(null, manager.currentIdentity)
    }

    @Test
    fun `running transition always restores ready state`() {
        val manager = EmbeddingModelSessionManager()
        val identity = identity()
        manager.getOrLoad(identity) {
            prepared(identity, SessionManagerFakeHandle())
        }

        assertThrows(IllegalArgumentException::class.java) {
            manager.run(identity, requestId = "request-1") {
                assertEquals(
                    SessionSlotState.Running(identity, "request-1"),
                    manager.state,
                )
                throw IllegalArgumentException("inference failed")
            }
        }

        assertEquals(SessionSlotState.Ready(identity), manager.state)
    }

    @Test
    fun `double release and close failure both clear references`() {
        val manager = EmbeddingModelSessionManager()
        val identity = identity()
        val handle = SessionManagerFakeHandle(
            onClose = { throw IllegalStateException("close sentinel") },
        )
        manager.getOrLoad(identity) {
            prepared(identity, handle)
        }

        assertThrows(IllegalStateException::class.java) {
            manager.release(identity.modelId)
        }
        manager.release(identity.modelId)

        assertEquals(1, handle.closeCount)
        assertEquals(SessionSlotState.Empty, manager.state)
    }

    @Test
    fun `terminal close is idempotent and rejects future loads`() {
        val manager = EmbeddingModelSessionManager()
        val identity = identity()
        val handle = SessionManagerFakeHandle()
        manager.getOrLoad(identity) {
            prepared(identity, handle)
        }

        manager.close()
        manager.close()

        assertEquals(1, handle.closeCount)
        assertEquals(SessionSlotState.Closed, manager.state)
        val error = assertThrows(EmbeddingRuntimeException::class.java) {
            manager.getOrLoad(identity) {
                prepared(identity, SessionManagerFakeHandle())
            }
        }
        assertEquals(EmbeddingRuntimeErrorCode.RUNTIME_CLOSED, error.code)
        assertTrue(error.message == "RUNTIME_CLOSED")
    }

    private fun identity(
        modelId: String = "embedding-model",
        modelPath: String = "C:/models/model.onnx",
        verifiedSha256: String = "sha256:${"a".repeat(64)}",
        tokenizerJsonSha256: String = "sha256:${"c".repeat(64)}",
        tokenizer: OnnxEmbeddingModelSpec.TokenizerSpec = tokenizerSpec(),
        runtime: OnnxEmbeddingModelSpec.RuntimeSpec = runtimeSpec(),
    ): SessionIdentity {
        return SessionIdentity(
            modelId = modelId,
            canonicalModelPath = modelPath,
            verifiedSha256 = verifiedSha256,
            tokenizerSpec = tokenizer,
            tokenizerJsonSha256 = tokenizerJsonSha256,
            runtimeSpec = runtime,
            executionSettings = OrtExecutionSettings(
                interOpThreads = 1,
                intraOpThreads = 2,
                strategyVersion = 1,
            ),
            runtimeImplementationVersion = 1,
        )
    }

    private fun prepared(
        identity: SessionIdentity,
        handle: OnnxSessionHandle,
    ): PreparedEmbeddingSession {
        return PreparedEmbeddingSession(
            identity = identity,
            tokenizer = WordpieceEmbeddingTokenizer(
                vocab = mapOf(
                    "[PAD]" to 0,
                    "[UNK]" to 100,
                    "[CLS]" to 101,
                    "[SEP]" to 102,
                ),
                lowercase = false,
                maxSequenceLength = 8,
            ),
            handle = handle,
            contract = contract(),
        )
    }

    private fun contract(): ModelIoContract {
        val input = IntegralInputContract(
            name = "input_ids",
            type = IntegralTensorType.INT64,
            shape = longArrayOf(1, -1),
        )
        return ModelIoContract(
            inputIds = input,
            attentionMask = input.copy(name = "attention_mask"),
            tokenTypeIds = input.copy(name = "token_type_ids"),
            outputName = "last_hidden_state",
            fixedSequenceLength = null,
            vectorDimension = 2,
        )
    }

    companion object {
        private fun tokenizerSpec() = OnnxEmbeddingModelSpec.TokenizerSpec(
            format = "tokenizer_json",
            assetPath = "assets/tokenizer.json",
            maxSequenceLength = 8,
            lowercase = false,
        )

        private fun runtimeSpec() = OnnxEmbeddingModelSpec.RuntimeSpec(
            inputIdsName = "input_ids",
            attentionMaskName = "attention_mask",
            tokenTypeIdsName = "token_type_ids",
            outputName = "last_hidden_state",
            pooling = "mean",
            normalization = "l2",
        )
    }
}

private class SessionManagerFakeHandle(
    private val onClose: () -> Unit = {},
) : OnnxSessionHandle {
    override val graph = ModelGraphInfo(inputs = emptyMap(), outputs = emptyMap())
    var closeCount = 0

    override fun run(
        inputs: Map<String, IntegralTensorData>,
        outputName: String,
        cancellation: CancellationHandle,
    ): FloatTensorData {
        throw AssertionError("run should not be called")
    }

    override fun close() {
        if (closeCount == 0) {
            closeCount += 1
            onClose()
        }
    }
}
