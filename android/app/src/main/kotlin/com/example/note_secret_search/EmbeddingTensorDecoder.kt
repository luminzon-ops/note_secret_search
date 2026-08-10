package com.example.note_secret_search

enum class EmbeddingTensorKind {
    TOKEN,
    SENTENCE,
}

data class DecodedEmbeddingTensor(
    val kind: EmbeddingTensorKind,
    val tokenVectors: Array<FloatArray> = emptyArray(),
    val sentenceVector: FloatArray = floatArrayOf(),
)

object EmbeddingTensorDecoder {
    fun decode(
        type: ModelTensorType,
        shape: LongArray,
        value: Any,
    ): DecodedEmbeddingTensor {
        require(type == ModelTensorType.FLOAT) {
            "INVALID_OUTPUT: embedding output must contain FLOAT values"
        }
        return when (shape.size) {
            2 -> decodeSentence(shape, value)
            3 -> decodeTokens(shape, value)
            else -> throw IllegalArgumentException(
                "INVALID_OUTPUT: embedding output rank must be 2 or 3",
            )
        }
    }

    fun decode(tensor: FloatTensorData): DecodedEmbeddingTensor {
        val shape = tensor.shape
        return when (shape.size) {
            2 -> {
                require(shape[0] == 1L && shape[1] > 0L) {
                    "INVALID_OUTPUT: sentence output shape must be [1, D]"
                }
                require(tensor.values.size == shape[1].toInt()) {
                    "INVALID_OUTPUT: sentence output shape does not match its values"
                }
                require(tensor.values.all(Float::isFinite)) {
                    "INVALID_OUTPUT: sentence output contains non-finite values"
                }
                DecodedEmbeddingTensor(
                    kind = EmbeddingTensorKind.SENTENCE,
                    sentenceVector = tensor.values.copyOf(),
                )
            }

            3 -> {
                require(shape[0] == 1L && shape[1] > 0L && shape[2] > 0L) {
                    "INVALID_OUTPUT: token output shape must be [1, S, D]"
                }
                val sequenceLength = shape[1].toInt()
                val width = shape[2].toInt()
                require(tensor.values.size == sequenceLength * width) {
                    "INVALID_OUTPUT: token output shape does not match its values"
                }
                require(tensor.values.all(Float::isFinite)) {
                    "INVALID_OUTPUT: token output contains non-finite values"
                }
                DecodedEmbeddingTensor(
                    kind = EmbeddingTensorKind.TOKEN,
                    tokenVectors = Array(sequenceLength) { index ->
                        tensor.values.copyOfRange(index * width, (index + 1) * width)
                    },
                )
            }

            else -> throw IllegalArgumentException(
                "INVALID_OUTPUT: embedding output rank must be 2 or 3",
            )
        }
    }

    private fun decodeSentence(
        shape: LongArray,
        value: Any,
    ): DecodedEmbeddingTensor {
        require(shape[0] == 1L && shape[1] > 0L) {
            "INVALID_OUTPUT: sentence output shape must be [1, D]"
        }
        val batch = value as? Array<*>
            ?: throw IllegalArgumentException("INVALID_OUTPUT: sentence output carrier is unsupported")
        require(batch.size == 1) {
            "INVALID_OUTPUT: sentence output batch must be 1"
        }
        val vector = batch[0] as? FloatArray
            ?: throw IllegalArgumentException("INVALID_OUTPUT: sentence output carrier is unsupported")
        require(vector.size == shape[1].toInt()) {
            "INVALID_OUTPUT: sentence output shape does not match its values"
        }
        require(vector.all(Float::isFinite)) {
            "INVALID_OUTPUT: sentence output contains non-finite values"
        }
        return DecodedEmbeddingTensor(
            kind = EmbeddingTensorKind.SENTENCE,
            sentenceVector = vector.copyOf(),
        )
    }

    private fun decodeTokens(
        shape: LongArray,
        value: Any,
    ): DecodedEmbeddingTensor {
        require(shape[0] == 1L && shape[1] > 0L && shape[2] > 0L) {
            "INVALID_OUTPUT: token output shape must be [1, S, D]"
        }
        val batch = value as? Array<*>
            ?: throw IllegalArgumentException("INVALID_OUTPUT: token output carrier is unsupported")
        require(batch.size == 1) {
            "INVALID_OUTPUT: token output batch must be 1"
        }
        val rows = batch[0] as? Array<*>
            ?: throw IllegalArgumentException("INVALID_OUTPUT: token output carrier is unsupported")
        require(rows.size == shape[1].toInt()) {
            "INVALID_OUTPUT: token output sequence does not match its shape"
        }
        val width = shape[2].toInt()
        val copied = Array(rows.size) { index ->
            val row = rows[index] as? FloatArray
                ?: throw IllegalArgumentException("INVALID_OUTPUT: token output carrier is unsupported")
            require(row.size == width) {
                "INVALID_OUTPUT: token output is ragged"
            }
            require(row.all(Float::isFinite)) {
                "INVALID_OUTPUT: token output contains non-finite values"
            }
            row.copyOf()
        }
        return DecodedEmbeddingTensor(
            kind = EmbeddingTensorKind.TOKEN,
            tokenVectors = copied,
        )
    }
}
