package com.example.note_secret_search

data class SessionIdentity(
    val modelId: String,
    val canonicalModelPath: String,
    val verifiedSha256: String,
    val tokenizerSpec: OnnxEmbeddingModelSpec.TokenizerSpec,
    val tokenizerJsonSha256: String,
    val runtimeSpec: OnnxEmbeddingModelSpec.RuntimeSpec,
    val executionSettings: OrtExecutionSettings,
    val runtimeImplementationVersion: Int,
) {
    init {
        require(modelId.isNotBlank())
        require(canonicalModelPath.isNotBlank())
        require(SHA256_PATTERN.matches(verifiedSha256))
        require(SHA256_PATTERN.matches(tokenizerJsonSha256))
        require(runtimeImplementationVersion > 0)
    }

    companion object {
        private val SHA256_PATTERN = Regex("^sha256:[0-9a-f]{64}$")
    }
}

sealed interface SessionSlotState {
    data object Empty : SessionSlotState

    data class Loading(val identity: SessionIdentity) : SessionSlotState

    data class Ready(val identity: SessionIdentity) : SessionSlotState

    data class Running(
        val identity: SessionIdentity,
        val requestId: String,
    ) : SessionSlotState

    data object Closing : SessionSlotState

    data object Closed : SessionSlotState
}
