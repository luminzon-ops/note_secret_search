package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OnnxEmbeddingModelSpecTest {
    @Test
    fun `fromMaps parses tokenizer and runtime metadata`() {
        val spec = OnnxEmbeddingModelSpec.fromMaps(
            tokenizer = mapOf(
                "format" to "tokenizer_json",
                "assetPath" to "assets/model_catalog/tokenizers/all_minilm/tokenizer.json",
                "maxSequenceLength" to 256,
                "lowercase" to true,
            ),
            runtime = mapOf(
                "inputIdsName" to "input_ids",
                "attentionMaskName" to "attention_mask",
                "outputName" to "last_hidden_state",
                "pooling" to "mean",
                "normalization" to "l2",
            ),
        )

        requireNotNull(spec)
        assertEquals("tokenizer_json", spec.tokenizer.format)
        assertEquals(256, spec.tokenizer.maxSequenceLength)
        assertEquals("input_ids", spec.runtime.inputIdsName)
        assertNull(spec.runtime.tokenTypeIdsName)
        assertEquals("mean", spec.runtime.pooling)
    }

    @Test
    fun `fromMaps returns null when tokenizer metadata is incomplete`() {
        val spec = OnnxEmbeddingModelSpec.fromMaps(
            tokenizer = mapOf(
                "format" to "tokenizer_json",
                "maxSequenceLength" to 256,
            ),
            runtime = mapOf(
                "inputIdsName" to "input_ids",
                "attentionMaskName" to "attention_mask",
                "outputName" to "last_hidden_state",
                "pooling" to "mean",
                "normalization" to "l2",
            ),
        )

        assertNull(spec)
    }
}
