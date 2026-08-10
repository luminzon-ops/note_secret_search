package com.example.note_secret_search

import java.io.File
import java.util.concurrent.CompletableFuture

internal class LlmLoadOperation(
    val identity: LlmSessionIdentity,
    val file: File,
    val config: LocalLlmGenerationConfig,
    val epoch: Long,
    val ensureWaiters: MutableList<CompletableFuture<Map<String, Any?>>> = mutableListOf(),
    var generation: LlmGenerationOperation? = null,
) {
    var releaseAfterLoad: Boolean = false
    val releaseWaiters: MutableList<CompletableFuture<Unit>> = mutableListOf()
}

internal class LlmGenerationOperation(
    val identity: LlmSessionIdentity,
    val requestId: String,
    val prompt: String,
    val usedPrivateContext: Boolean,
    val config: LocalLlmGenerationConfig,
    val future: CompletableFuture<Map<String, Any?>>,
) {
    var session: LocalLlmBackendSession? = null
    var epoch: Long? = null
    var cancelRequested: Boolean = false
    var cancelSent: Boolean = false
    var releaseRequested: Boolean = false
    val releaseWaiters: MutableList<CompletableFuture<Unit>> = mutableListOf()
    var readinessSwitch: LlmLoadOperation? = null
}

internal class LlmReleaseOperation(
    val session: LocalLlmBackendSession,
    val identity: LlmSessionIdentity,
    val epoch: Long,
    val waiters: MutableList<CompletableFuture<Unit>>,
    val continuations: MutableList<LlmReleaseContinuation>,
)

internal class LlmReleaseContinuation(
    val onSuccess: () -> Unit,
    val onFailure: (LlmRuntimeException) -> Unit,
)

internal fun llmBusyError(
    modelId: String,
    requestId: String? = null,
): LlmRuntimeException {
    return LlmRuntimeException(
        code = LlmRuntimeErrorCode.BUSY,
        stage = LlmRuntimeStage.LIFECYCLE,
        modelId = modelId,
        requestId = requestId,
    )
}

internal fun llmClosedError(
    modelId: String? = null,
    requestId: String? = null,
): LlmRuntimeException {
    return LlmRuntimeException(
        code = LlmRuntimeErrorCode.RUNTIME_CLOSED,
        stage = LlmRuntimeStage.LIFECYCLE,
        modelId = modelId,
        requestId = requestId,
    )
}

internal fun llmCancelledError(
    modelId: String,
    requestId: String,
): LlmRuntimeException {
    return LlmRuntimeException(
        code = LlmRuntimeErrorCode.CANCELLED,
        stage = LlmRuntimeStage.CANCELLATION,
        modelId = modelId,
        requestId = requestId,
    )
}

internal fun currentLlmIdentity(state: LlmLifecycleState): LlmSessionIdentity? {
    return when (state) {
        is LlmLifecycleState.Loading -> state.identity
        is LlmLifecycleState.Ready -> state.identity
        is LlmLifecycleState.Generating -> state.identity
        is LlmLifecycleState.Cancelling -> state.identity
        is LlmLifecycleState.Releasing -> state.identity
        LlmLifecycleState.Empty,
        LlmLifecycleState.Closed,
        -> null
    }
}

internal fun currentLlmEpoch(state: LlmLifecycleState): Long? {
    return when (state) {
        is LlmLifecycleState.Loading -> state.epoch
        is LlmLifecycleState.Ready -> state.epoch
        is LlmLifecycleState.Generating -> state.epoch
        is LlmLifecycleState.Cancelling -> state.epoch
        is LlmLifecycleState.Releasing -> state.epoch
        LlmLifecycleState.Empty,
        LlmLifecycleState.Closed,
        -> null
    }
}

internal fun <T> completeLlmResult(
    future: CompletableFuture<T>,
    result: Result<T>,
) {
    result.fold(
        onSuccess = future::complete,
        onFailure = future::completeExceptionally,
    )
}
