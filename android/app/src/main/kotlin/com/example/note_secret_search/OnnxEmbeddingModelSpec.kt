package com.example.note_secret_search

data class OnnxEmbeddingModelSpec(
    val tokenizer: TokenizerSpec,
    val runtime: RuntimeSpec,
) {
    data class TokenizerSpec(
        val format: String,
        val assetPath: String,
        val maxSequenceLength: Int,
        val lowercase: Boolean,
    )

    data class RuntimeSpec(
        val inputIdsName: String,
        val attentionMaskName: String,
        val tokenTypeIdsName: String?,
        val outputName: String,
        val pooling: String,
        val normalization: String,
    )

    companion object {
        fun fromMaps(
            tokenizer: Map<*, *>?,
            runtime: Map<*, *>?,
        ): OnnxEmbeddingModelSpec? {
            val tokenizerSpec = tokenizer?.toTokenizerSpec() ?: return null
            val runtimeSpec = runtime?.toRuntimeSpec() ?: return null
            return OnnxEmbeddingModelSpec(tokenizer = tokenizerSpec, runtime = runtimeSpec)
        }

        private fun Map<*, *>.toTokenizerSpec(): TokenizerSpec? {
            val format = this["format"] as? String ?: return null
            val assetPath = this["assetPath"] as? String ?: return null
            val maxSequenceLength = (this["maxSequenceLength"] as? Number)?.toInt() ?: return null
            val lowercase = this["lowercase"] as? Boolean ?: false
            if (format.isBlank() || assetPath.isBlank() || maxSequenceLength <= 0) {
                return null
            }

            return TokenizerSpec(
                format = format,
                assetPath = assetPath,
                maxSequenceLength = maxSequenceLength,
                lowercase = lowercase,
            )
        }

        private fun Map<*, *>.toRuntimeSpec(): RuntimeSpec? {
            val inputIdsName = this["inputIdsName"] as? String ?: return null
            val attentionMaskName = this["attentionMaskName"] as? String ?: return null
            val tokenTypeIdsName = this["tokenTypeIdsName"] as? String
            val outputName = this["outputName"] as? String ?: return null
            val pooling = this["pooling"] as? String ?: return null
            val normalization = this["normalization"] as? String ?: return null
            if (
                inputIdsName.isBlank() ||
                attentionMaskName.isBlank() ||
                outputName.isBlank() ||
                pooling.isBlank() ||
                normalization.isBlank()
            ) {
                return null
            }

            return RuntimeSpec(
                inputIdsName = inputIdsName,
                attentionMaskName = attentionMaskName,
                tokenTypeIdsName = tokenTypeIdsName?.takeIf { it.isNotBlank() },
                outputName = outputName,
                pooling = pooling,
                normalization = normalization,
            )
        }
    }
}
