package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ModelIoContractBuilderTest {
    @Test
    fun `build accepts dynamic INT64 BERT inputs and rank three FLOAT output`() {
        val contract = ModelIoContractBuilder.build(
            graph = ModelGraphInfo(
                inputs = mapOf(
                    "input_ids" to tensor(ModelTensorType.INT64, -1, -1),
                    "attention_mask" to tensor(ModelTensorType.INT64, -1, -1),
                    "token_type_ids" to tensor(ModelTensorType.INT64, -1, -1),
                ),
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.FLOAT, -1, -1, 384),
                ),
            ),
            runtime = runtimeSpec(),
        )

        assertEquals(IntegralTensorType.INT64, contract.inputIds.type)
        assertEquals(IntegralTensorType.INT64, contract.attentionMask.type)
        assertEquals(IntegralTensorType.INT64, contract.tokenTypeIds?.type)
        assertNull(contract.fixedSequenceLength)
        assertEquals(384, contract.vectorDimension)
        assertEquals("last_hidden_state", contract.outputName)
    }

    @Test
    fun `build accepts fixed INT32 inputs and records graph sequence length`() {
        val contract = ModelIoContractBuilder.build(
            graph = ModelGraphInfo(
                inputs = mapOf(
                    "input_ids" to tensor(ModelTensorType.INT32, 1, 8),
                    "attention_mask" to tensor(ModelTensorType.INT32, 1, 8),
                    "token_type_ids" to tensor(ModelTensorType.INT32, 1, 8),
                ),
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, 8, 4),
                ),
            ),
            runtime = runtimeSpec(),
        )

        assertEquals(IntegralTensorType.INT32, contract.inputIds.type)
        assertEquals(IntegralTensorType.INT32, contract.attentionMask.type)
        assertEquals(IntegralTensorType.INT32, contract.tokenTypeIds?.type)
        assertEquals(8, contract.fixedSequenceLength)
        assertEquals(4, contract.vectorDimension)
    }

    @Test
    fun `build uses fixed output sequence when all inputs are dynamic`() {
        val graph = ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to tensor(ModelTensorType.INT64, 1, -1),
                "attention_mask" to tensor(ModelTensorType.INT64, 1, -1),
                "token_type_ids" to tensor(ModelTensorType.INT64, 1, -1),
            ),
            outputs = mapOf(
                "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, 8, 4),
            ),
        )

        val contract = ModelIoContractBuilder.build(graph = graph, runtime = runtimeSpec())

        assertEquals(8, contract.fixedSequenceLength)
    }

    @Test
    fun `build rejects duplicate runtime input names`() {
        val graph = ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to tensor(ModelTensorType.INT64, 1, -1),
                "attention_mask" to tensor(ModelTensorType.INT64, 1, -1),
            ),
            outputs = mapOf(
                "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, -1, 4),
            ),
        )
        val duplicateNames = runtimeSpec().copy(
            tokenTypeIdsName = "attention_mask",
        )

        assertThrows(IllegalArgumentException::class.java) {
            ModelIoContractBuilder.build(graph = graph, runtime = duplicateNames)
        }
    }

    @Test
    fun `build rejects malformed or conflicting model IO contracts`() {
        val malformedGraphs = listOf(
            validGraph().copy(
                inputs = validGraph().inputs + ("input_ids" to tensor(ModelTensorType.INT64, 8)),
            ),
            validGraph().copy(
                inputs = validGraph().inputs + ("input_ids" to tensor(ModelTensorType.INT64, 2, 8)),
            ),
            validGraph().copy(
                inputs = validGraph().inputs + ("input_ids" to tensor(ModelTensorType.INT64, 1, 0)),
            ),
            validGraph().copy(
                inputs = validGraph().inputs + ("attention_mask" to tensor(ModelTensorType.INT64, 1, 16)),
            ),
            validGraph().copy(
                inputs = validGraph().inputs + ("position_ids" to tensor(ModelTensorType.INT64, 1, 8)),
            ),
            validGraph().copy(outputs = emptyMap()),
            validGraph().copy(
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.INT64, 1, 8, 4),
                ),
            ),
            validGraph().copy(
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, 4),
                ),
            ),
            validGraph().copy(
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.FLOAT, 2, 8, 4),
                ),
            ),
            validGraph().copy(
                outputs = mapOf(
                    "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, 16, 4),
                ),
            ),
        )

        malformedGraphs.forEach { graph ->
            assertThrows(IllegalArgumentException::class.java) {
                ModelIoContractBuilder.build(graph = graph, runtime = runtimeSpec())
            }
        }
    }

    private fun validGraph(): ModelGraphInfo {
        return ModelGraphInfo(
            inputs = mapOf(
                "input_ids" to tensor(ModelTensorType.INT64, 1, 8),
                "attention_mask" to tensor(ModelTensorType.INT64, 1, 8),
                "token_type_ids" to tensor(ModelTensorType.INT64, 1, 8),
            ),
            outputs = mapOf(
                "last_hidden_state" to tensor(ModelTensorType.FLOAT, 1, 8, 4),
                "decoy" to tensor(ModelTensorType.FLOAT, 1, 1),
            ),
        )
    }

    private fun tensor(type: ModelTensorType, vararg shape: Long): ModelTensorInfo {
        return ModelTensorInfo(type = type, shape = shape)
    }

    private fun runtimeSpec(): OnnxEmbeddingModelSpec.RuntimeSpec {
        return OnnxEmbeddingModelSpec.RuntimeSpec(
            inputIdsName = "input_ids",
            attentionMaskName = "attention_mask",
            tokenTypeIdsName = "token_type_ids",
            outputName = "last_hidden_state",
            pooling = "mean",
            normalization = "l2",
        )
    }
}
