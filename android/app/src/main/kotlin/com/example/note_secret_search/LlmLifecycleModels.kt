package com.example.note_secret_search

internal const val DEFAULT_LLM_RUNTIME_BUILD_ID = "llamacpp-kotlin-0.2.0-huawei-safe"

data class LlmLoadConfig(
    val contextLength: Int,
    val conservativeMode: Boolean,
)

data class LlmSessionIdentity(
    val modelId: String,
    val canonicalModelPath: String,
    val verifiedChecksum: String?,
    val runtimeBuildId: String,
    val loadConfig: LlmLoadConfig,
)

sealed interface LlmLifecycleState {
    data object Empty : LlmLifecycleState

    data class Loading(
        val identity: LlmSessionIdentity,
        val epoch: Long,
    ) : LlmLifecycleState

    data class Ready(
        val identity: LlmSessionIdentity,
        val epoch: Long,
    ) : LlmLifecycleState

    data class Generating(
        val identity: LlmSessionIdentity,
        val epoch: Long,
        val requestId: String,
    ) : LlmLifecycleState

    data class Cancelling(
        val identity: LlmSessionIdentity,
        val epoch: Long,
        val requestId: String,
    ) : LlmLifecycleState

    data class Releasing(
        val identity: LlmSessionIdentity,
        val epoch: Long,
    ) : LlmLifecycleState

    data object Closed : LlmLifecycleState
}

data class LlmLifecycleSnapshot(
    val state: LlmLifecycleState,
    val sessionEpoch: Long,
    val activeRequestId: String?,
)
