package com.example.note_secret_search

import kotlin.math.sqrt

object EmbeddingVectorPostProcessor {
    fun pool(
        tokenVectors: Array<FloatArray>,
        attentionMask: LongArray,
        pooling: String,
    ): List<Double> {
        validateTokenVectors(tokenVectors, attentionMask)

        return when (pooling) {
            "cls" -> {
                val firstValid = attentionMask.indexOfFirst { it == 1L }
                require(firstValid >= 0) {
                    "INVALID_OUTPUT: attention mask has no valid tokens"
                }
                tokenVectors[firstValid].map(Float::toDouble)
            }
            "mean" -> meanPool(tokenVectors, attentionMask)
            else -> throw IllegalArgumentException(
                "INVALID_OUTPUT: unsupported embedding pooling",
            )
        }
    }

    fun normalize(values: List<Double>, normalization: String): List<Double> {
        require(values.isNotEmpty()) {
            "INVALID_OUTPUT: embedding vector is empty"
        }
        require(values.all(Double::isFinite)) {
            "INVALID_OUTPUT: embedding vector contains non-finite values"
        }
        if (normalization == "none") {
            return values.toList()
        }
        require(normalization == "l2") {
            "INVALID_OUTPUT: unsupported embedding normalization"
        }

        val norm = sqrt(values.sumOf { it * it })
        require(norm.isFinite() && norm > 0.0) {
            "INVALID_OUTPUT: embedding vector has zero or invalid norm"
        }

        return values.map { it / norm }
    }

    private fun validateTokenVectors(
        tokenVectors: Array<FloatArray>,
        attentionMask: LongArray,
    ) {
        require(tokenVectors.isNotEmpty()) {
            "INVALID_OUTPUT: token output is empty"
        }
        require(attentionMask.size == tokenVectors.size) {
            "INVALID_OUTPUT: attention mask does not match token output"
        }
        require(attentionMask.all { it == 0L || it == 1L }) {
            "INVALID_OUTPUT: attention mask contains unsupported values"
        }
        val width = tokenVectors.first().size
        require(width > 0) {
            "INVALID_OUTPUT: token vector dimension is empty"
        }
        require(tokenVectors.all { row -> row.size == width }) {
            "INVALID_OUTPUT: token output is ragged"
        }
        require(tokenVectors.all { row -> row.all(Float::isFinite) }) {
            "INVALID_OUTPUT: token output contains non-finite values"
        }
    }

    private fun meanPool(
        tokenVectors: Array<FloatArray>,
        attentionMask: LongArray,
    ): List<Double> {
        val width = tokenVectors.firstOrNull()?.size ?: return emptyList()
        val totals = DoubleArray(width)
        var counted = 0

        for (index in tokenVectors.indices) {
            if (index >= attentionMask.size || attentionMask[index] == 0L) {
                continue
            }
            counted++
            val row = tokenVectors[index]
            for (offset in row.indices) {
                totals[offset] += row[offset].toDouble()
            }
        }

        if (counted == 0) {
            throw IllegalArgumentException(
                "INVALID_OUTPUT: attention mask has no valid tokens",
            )
        }

        return totals.map { it / counted }
    }
}
