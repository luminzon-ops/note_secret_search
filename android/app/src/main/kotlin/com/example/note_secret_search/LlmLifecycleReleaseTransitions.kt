package com.example.note_secret_search

import java.util.concurrent.CompletableFuture

internal fun LlmLifecycleActor.handleRelease(
    modelId: String,
    future: CompletableFuture<Unit>,
) {
    if (lifecycleState == LlmLifecycleState.Closed) {
        future.complete(Unit)
        return
    }
    when (val state = lifecycleState) {
        LlmLifecycleState.Empty -> future.complete(Unit)
        is LlmLifecycleState.Loading -> {
            val operation = pendingLoad
            if (operation != null && state.identity.modelId == modelId) {
                operation.releaseAfterLoad = true
                operation.releaseWaiters += future
                operation.generation?.let {
                    it.cancelRequested = true
                    it.releaseRequested = true
                }
            } else {
                future.complete(Unit)
            }
        }
        is LlmLifecycleState.Ready -> {
            if (state.identity.modelId == modelId) {
                startReleaseForCurrent(listOf(future), null)
            } else {
                future.complete(Unit)
            }
        }
        is LlmLifecycleState.Generating,
        is LlmLifecycleState.Cancelling,
        -> {
            val generation = activeGeneration
            if (generation == null || currentLlmIdentity(state)?.modelId != modelId) {
                future.complete(Unit)
            } else {
                generation.releaseRequested = true
                generation.releaseWaiters += future
                requestCancellation(generation)
            }
        }
        is LlmLifecycleState.Releasing -> {
            val operation = releaseOperation
            if (operation?.identity?.modelId == modelId) {
                operation.waiters += future
            } else {
                future.complete(Unit)
            }
        }
        LlmLifecycleState.Closed -> future.complete(Unit)
    }
}

internal fun LlmLifecycleActor.switchTo(
    identity: LlmSessionIdentity,
    continuation: LlmReleaseContinuation,
) {
    val state = lifecycleState as? LlmLifecycleState.Ready
    if (state == null || state.identity == identity) {
        continuation.onSuccess()
        return
    }
    val session = sessionManager.take(state.identity.modelId)
    if (session == null) {
        lifecycleState = LlmLifecycleState.Empty
        continuation.onSuccess()
        return
    }
    startRelease(
        session = session,
        identity = state.identity,
        epoch = state.epoch,
        waiters = mutableListOf(),
        continuations = mutableListOf(continuation),
    )
}

internal fun LlmLifecycleActor.startReleaseForCurrent(
    waiters: List<CompletableFuture<Unit>>,
    continuation: LlmReleaseContinuation?,
) {
    val state = lifecycleState
    val identity = currentLlmIdentity(state)
    val epoch = currentLlmEpoch(state)
    if (identity == null || epoch == null) {
        waiters.forEach { it.complete(Unit) }
        continuation?.onSuccess?.invoke()
        if (closeRequested.get()) {
            finishClosed()
        }
        return
    }
    val session = sessionManager.take(identity.modelId)
    if (session == null) {
        lifecycleState = LlmLifecycleState.Empty
        waiters.forEach { it.complete(Unit) }
        continuation?.onSuccess?.invoke()
        if (closeRequested.get()) {
            finishClosed()
        }
        return
    }
    startRelease(
        session = session,
        identity = identity,
        epoch = epoch,
        waiters = waiters.toMutableList(),
        continuations = mutableListOfNotNull(continuation),
    )
}

internal fun LlmLifecycleActor.startRelease(
    session: LocalLlmBackendSession,
    identity: LlmSessionIdentity,
    epoch: Long,
    waiters: MutableList<CompletableFuture<Unit>>,
    continuations: MutableList<LlmReleaseContinuation>,
) {
    val operation = LlmReleaseOperation(
        session = session,
        identity = identity,
        epoch = epoch,
        waiters = waiters,
        continuations = continuations,
    )
    releaseOperation = operation
    lifecycleState = LlmLifecycleState.Releasing(identity, epoch)
    try {
        nativeExecutor.execute {
            try {
                session.backend.release(session)
                postLifecycle { finishRelease(operation, null) }
            } catch (error: Throwable) {
                postLifecycle {
                    finishRelease(
                        operation = operation,
                        error = LlmRuntimeException.wrap(
                            error = error,
                            code = LlmRuntimeErrorCode.RELEASE_FAILED,
                            stage = LlmRuntimeStage.RELEASE,
                            modelId = identity.modelId,
                        ),
                    )
                }
            }
        }
    } catch (error: Throwable) {
        finishRelease(
            operation = operation,
            error = LlmRuntimeException.wrap(
                error = error,
                code = LlmRuntimeErrorCode.RELEASE_FAILED,
                stage = LlmRuntimeStage.RELEASE,
                modelId = identity.modelId,
            ),
        )
    }
}

internal fun LlmLifecycleActor.finishRelease(
    operation: LlmReleaseOperation,
    error: LlmRuntimeException?,
) {
    if (releaseOperation !== operation) {
        return
    }
    releaseOperation = null
    if (error == null) {
        lifecycleState = LlmLifecycleState.Empty
        operation.waiters.forEach { it.complete(Unit) }
        operation.continuations.forEach { it.onSuccess() }
    } else {
        lifecycleState = LlmLifecycleState.Closed
        nativeExecutor.shutdown()
        controlExecutor.shutdown()
        lifecycleExecutor.shutdown()
        operation.waiters.forEach { it.completeExceptionally(error) }
        operation.continuations.forEach { it.onFailure(error) }
        closeFailure = closeFailure ?: error
    }
    if (closeRequested.get() && pendingLoad == null && activeGeneration == null) {
        if (error == null) {
            finishClosed()
        } else {
            completeCloseFuture()
        }
    }
}

internal fun LlmLifecycleActor.requestCancellation(generation: LlmGenerationOperation) {
    generation.cancelRequested = true
    val epoch = generation.epoch
    if (
        epoch != null &&
        lifecycleState is LlmLifecycleState.Generating &&
        activeGeneration === generation
    ) {
        lifecycleState = LlmLifecycleState.Cancelling(
            identity = generation.identity,
            epoch = epoch,
            requestId = generation.requestId,
        )
    }
    if (generation.cancelSent) {
        return
    }
    val session = generation.session ?: return
    generation.cancelSent = true
    runCatching {
        controlExecutor.execute {
            runCatching { session.backend.cancel(session) }
        }
    }
}

internal fun LlmLifecycleActor.finishCancelledGenerationAfterLoad(
    generation: LlmGenerationOperation,
) {
    generation.cancelRequested = true
    generation.releaseRequested = true
    val waiters = generation.releaseWaiters.toList()
    generation.releaseWaiters.clear()
    val readinessSwitch = generation.readinessSwitch
    generation.readinessSwitch = null
    startReleaseForCurrent(
        waiters = waiters,
        continuation = LlmReleaseContinuation(
            onSuccess = {
                activeGeneration = null
                generation.future.completeExceptionally(
                    llmCancelledError(generation.identity.modelId, generation.requestId),
                )
                if (readinessSwitch != null && !closeRequested.get()) {
                    startLoad(readinessSwitch)
                } else if (readinessSwitch != null) {
                    readinessSwitch.ensureWaiters.forEach {
                        it.completeExceptionally(
                            llmClosedError(readinessSwitch.identity.modelId),
                        )
                    }
                }
            },
            onFailure = { releaseError ->
                activeGeneration = null
                generation.future.completeExceptionally(
                    releaseError.withRequestId(generation.requestId),
                )
                readinessSwitch?.ensureWaiters?.forEach {
                    it.completeExceptionally(
                        releaseError.withModelId(readinessSwitch.identity.modelId),
                    )
                }
            },
        ),
    )
}

internal fun LlmLifecycleActor.handleClose() {
    when (lifecycleState) {
        LlmLifecycleState.Empty,
        LlmLifecycleState.Closed,
        -> finishClosed()
        is LlmLifecycleState.Loading -> {
            pendingLoad?.let { operation ->
                operation.releaseAfterLoad = true
                operation.generation?.let {
                    it.cancelRequested = true
                    it.releaseRequested = true
                }
            } ?: finishClosed()
        }
        is LlmLifecycleState.Ready -> startReleaseForCurrent(emptyList(), null)
        is LlmLifecycleState.Generating,
        is LlmLifecycleState.Cancelling,
        -> activeGeneration?.let {
            it.releaseRequested = true
            requestCancellation(it)
        } ?: finishClosed()
        is LlmLifecycleState.Releasing -> Unit
    }
}

internal fun LlmLifecycleActor.finishClosed() {
    if (lifecycleState == LlmLifecycleState.Closed) {
        completeCloseFuture()
        return
    }
    if (pendingLoad != null || activeGeneration != null || releaseOperation != null) {
        return
    }
    lifecycleState = LlmLifecycleState.Closed
    nativeExecutor.shutdown()
    controlExecutor.shutdown()
    completeCloseFuture()
    lifecycleExecutor.shutdown()
}

private fun LlmLifecycleActor.completeCloseFuture() {
    val error = closeFailure
    if (error == null) {
        closeFuture?.complete(Unit)
    } else {
        closeFuture?.completeExceptionally(error)
    }
}

private fun <T> mutableListOfNotNull(value: T?): MutableList<T> {
    return if (value == null) mutableListOf() else mutableListOf(value)
}
