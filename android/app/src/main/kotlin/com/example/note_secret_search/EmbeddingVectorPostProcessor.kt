package com.example.note_secret_search

import kotlin.math.sqrt

object EmbeddingVectorPostProcessor {
    fun pool(
        tokenVectors: Array<FloatArray>,
        attentionMask: LongArray,
        pooling: String,
    ): List<Double> {
        if (tokenVectors.isEmpty()) {
            return emptyList()
        }

        return when (pooling) {
            "cls" -> tokenVectors.first().map(Float::toDouble)
            "mean" -> meanPool(tokenVectors, attentionMask)
            else -> tokenVectors.first().map(Float::toDouble)
        }
    }

    fun normalize(values: List<Double>, normalization: String): List<Double> {
        if (normalization != "l2") {
            return values
        }

        val norm = sqrt(values.sumOf { it * it })
        if (norm == 0.0) {
            return values
        }

        return values.map { it / norm }
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
            return List(width) { 0.0 }
        }

        return totals.map { it / counted }
    }
}
