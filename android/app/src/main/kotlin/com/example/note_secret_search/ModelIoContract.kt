package com.example.note_secret_search

enum class ModelTensorType {
    FLOAT,
    INT32,
    INT64,
    UNSUPPORTED,
}

data class ModelTensorInfo(
    val type: ModelTensorType,
    val shape: LongArray,
)

data class ModelGraphInfo(
    val inputs: Map<String, ModelTensorInfo>,
    val outputs: Map<String, ModelTensorInfo>,
)

enum class IntegralTensorType {
    INT32,
    INT64,
}

data class IntegralInputContract(
    val name: String,
    val type: IntegralTensorType,
    val shape: LongArray,
)

data class ModelIoContract(
    val inputIds: IntegralInputContract,
    val attentionMask: IntegralInputContract,
    val tokenTypeIds: IntegralInputContract?,
    val outputName: String,
    val fixedSequenceLength: Int?,
    val vectorDimension: Int,
)

object ModelIoContractBuilder {
    fun build(
        graph: ModelGraphInfo,
        runtime: OnnxEmbeddingModelSpec.RuntimeSpec,
    ): ModelIoContract {
        val configuredInputNames = listOfNotNull(
            runtime.inputIdsName,
            runtime.attentionMaskName,
            runtime.tokenTypeIdsName,
        )
        require(configuredInputNames.size == configuredInputNames.distinct().size) {
            "MODEL_SCHEMA_UNSUPPORTED: runtime input names must be distinct"
        }
        val expectedInputNames = configuredInputNames.toSet()
        require(graph.inputs.keys == expectedInputNames) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding inputs do not match runtime metadata"
        }

        val inputIds = integralInput(graph, runtime.inputIdsName)
        val attentionMask = integralInput(graph, runtime.attentionMaskName)
        val tokenTypeIds = runtime.tokenTypeIdsName?.let { integralInput(graph, it) }
        val inputs = listOfNotNull(inputIds, attentionMask, tokenTypeIds)
        val fixedBatchDimensions = inputs.map { it.shape[0] }.filter { it > 0L }.toSet()
        val fixedSequenceDimensions = inputs.map { it.shape[1] }.filter { it > 0L }.toSet()
        require(fixedBatchDimensions.size <= 1 && fixedSequenceDimensions.size <= 1) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding input shapes conflict"
        }

        val output = requireNotNull(graph.outputs[runtime.outputName]) {
            "MODEL_SCHEMA_UNSUPPORTED: configured embedding output is missing"
        }
        require(output.type == ModelTensorType.FLOAT) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding output must be FLOAT"
        }
        val outputSequenceDimension: Long?
        val vectorDimension: Long
        when (output.shape.size) {
            2 -> {
                require(runtime.pooling == "none") {
                    "MODEL_SCHEMA_UNSUPPORTED: sentence output requires pooling=none"
                }
                require(
                    isBatchDimension(output.shape[0]) &&
                        output.shape[1] in 1..Int.MAX_VALUE.toLong(),
                ) {
                    "MODEL_SCHEMA_UNSUPPORTED: sentence output dimensions are invalid"
                }
                outputSequenceDimension = null
                vectorDimension = output.shape[1]
            }

            3 -> {
                require(runtime.pooling == "mean" || runtime.pooling == "cls") {
                    "MODEL_SCHEMA_UNSUPPORTED: token output requires mean or cls pooling"
                }
                require(isBatchDimension(output.shape[0])) {
                    "MODEL_SCHEMA_UNSUPPORTED: embedding output batch must be 1 or dynamic"
                }
                require(
                    isSequenceDimension(output.shape[1]) &&
                        output.shape[2] in 1..Int.MAX_VALUE.toLong(),
                ) {
                    "MODEL_SCHEMA_UNSUPPORTED: token output dimensions are invalid"
                }
                outputSequenceDimension = output.shape[1]
                vectorDimension = output.shape[2]
            }

            else -> throw IllegalArgumentException(
                "MODEL_SCHEMA_UNSUPPORTED: embedding output rank must be two or three",
            )
        }
        val fixedInputSequenceLength = fixedSequenceDimensions.singleOrNull()
        if (fixedInputSequenceLength != null && (outputSequenceDimension ?: -1L) > 0L) {
            require(outputSequenceDimension == fixedInputSequenceLength) {
                "MODEL_SCHEMA_UNSUPPORTED: embedding output sequence conflicts with inputs"
            }
        }
        val fixedSequenceLength = fixedInputSequenceLength
            ?: outputSequenceDimension?.takeIf { it > 0L }

        return ModelIoContract(
            inputIds = inputIds,
            attentionMask = attentionMask,
            tokenTypeIds = tokenTypeIds,
            outputName = runtime.outputName,
            fixedSequenceLength = fixedSequenceLength?.toInt(),
            vectorDimension = vectorDimension.toInt(),
        )
    }

    private fun integralInput(
        graph: ModelGraphInfo,
        name: String,
    ): IntegralInputContract {
        val input = requireNotNull(graph.inputs[name]) {
            "MODEL_SCHEMA_UNSUPPORTED: configured embedding input is missing"
        }
        require(input.shape.size == 2) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding inputs must be rank two"
        }
        require(isBatchDimension(input.shape[0])) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding input batch must be 1 or dynamic"
        }
        require(isSequenceDimension(input.shape[1])) {
            "MODEL_SCHEMA_UNSUPPORTED: embedding input sequence is invalid"
        }
        val type = when (input.type) {
            ModelTensorType.INT32 -> IntegralTensorType.INT32
            ModelTensorType.INT64 -> IntegralTensorType.INT64
            ModelTensorType.FLOAT,
            ModelTensorType.UNSUPPORTED,
            -> throw IllegalArgumentException(
                "MODEL_SCHEMA_UNSUPPORTED: embedding input must be integral",
            )
        }
        return IntegralInputContract(name = name, type = type, shape = input.shape.copyOf())
    }

    private fun isBatchDimension(value: Long): Boolean {
        return value == 1L || value == -1L
    }

    private fun isSequenceDimension(value: Long): Boolean {
        return value == -1L || value in 1..Int.MAX_VALUE.toLong()
    }
}
