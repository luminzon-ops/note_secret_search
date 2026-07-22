package com.example.note_secret_search

internal fun LlmLifecycleActor.startLoad(operation: LlmLoadOperation) {
    if (closeRequested.get()) {
        operation.ensureWaiters.forEach {
            it.completeExceptionally(llmClosedError(operation.identity.modelId))
        }
        operation.generation?.let {
            activeGeneration = null
            it.future.completeExceptionally(
                llmClosedError(it.identity.modelId, it.requestId),
            )
        }
        finishClosed()
        return
    }
    pendingLoad = operation
    lifecycleState = LlmLifecycleState.Loading(operation.identity, operation.epoch)
    try {
        nativeExecutor.execute {
            try {
                val backend = backendFactory.create(operation.file)
                    ?: throw LlmRuntimeException(
                        code = LlmRuntimeErrorCode.MODEL_UNSUPPORTED,
                        stage = LlmRuntimeStage.SESSION_LOAD,
                        modelId = operation.identity.modelId,
                    )
                val inspection = backend.inspect(operation.file)
                if (!inspection.supported) {
                    throw LlmRuntimeException(
                        code = LlmRuntimeErrorCode.MODEL_UNSUPPORTED,
                        stage = LlmRuntimeStage.SESSION_LOAD,
                        modelId = operation.identity.modelId,
                    )
                }
                val session = backend.load(
                    modelId = operation.identity.modelId,
                    file = operation.file,
                    config = operation.config,
                )
                postLifecycle {
                    handleLoadSuccess(operation, session)
                }
            } catch (error: Throwable) {
                postLifecycle {
                    handleLoadFailure(
                        operation = operation,
                        error = LlmRuntimeException.wrap(
                            error = error,
                            code = LlmRuntimeErrorCode.LOAD_FAILED,
                            stage = LlmRuntimeStage.SESSION_LOAD,
                            modelId = operation.identity.modelId,
                        ),
                    )
                }
            }
        }
    } catch (error: Throwable) {
        handleLoadFailure(
            operation = operation,
            error = LlmRuntimeException.wrap(
                error = error,
                code = LlmRuntimeErrorCode.LOAD_FAILED,
                stage = LlmRuntimeStage.SESSION_LOAD,
                modelId = operation.identity.modelId,
            ),
        )
    }
}

internal fun LlmLifecycleActor.handleLoadSuccess(
    operation: LlmLoadOperation,
    session: LocalLlmBackendSession,
) {
    if (pendingLoad !== operation) {
        runCatching {
            nativeExecutor.execute {
                runCatching { session.backend.release(session) }
            }
        }
        return
    }
    pendingLoad = null
    sessionManager.install(operation.identity.modelId, session)
    sessionEpoch = operation.epoch
    lifecycleState = LlmLifecycleState.Ready(operation.identity, operation.epoch)
    val ready = readyState(operation.identity)
    operation.ensureWaiters.forEach { it.complete(ready) }

    val generation = operation.generation
    if (generation != null) {
        if (operation.releaseAfterLoad) {
            generation.cancelRequested = true
            generation.releaseRequested = true
            generation.releaseWaiters += operation.releaseWaiters
            operation.releaseWaiters.clear()
        }
        if (generation.cancelRequested || closeRequested.get()) {
            finishCancelledGenerationAfterLoad(generation)
        } else {
            startGeneration(generation)
        }
    } else if (operation.releaseAfterLoad || closeRequested.get()) {
        val waiters = operation.releaseWaiters.toList()
        operation.releaseWaiters.clear()
        startReleaseForCurrent(waiters = waiters, continuation = null)
    }
}

internal fun LlmLifecycleActor.handleLoadFailure(
    operation: LlmLoadOperation,
    error: LlmRuntimeException,
) {
    if (pendingLoad !== operation) {
        return
    }
    pendingLoad = null
    lifecycleState = LlmLifecycleState.Empty
    operation.ensureWaiters.forEach {
        it.complete(
            runtimeState(
                status = "degraded",
                reason = if (error.code == LlmRuntimeErrorCode.MODEL_UNSUPPORTED) {
                    "当前模型格式暂无可用 Android 本地推理 backend。"
                } else {
                    "模型已安装但当前加载失败，请重新加载或切换模型。"
                },
                modelPath = operation.identity.canonicalModelPath,
                runtime = if (error.code == LlmRuntimeErrorCode.MODEL_UNSUPPORTED) {
                    "unsupported"
                } else {
                    "failed"
                },
            ),
        )
    }
    operation.generation?.let { generation ->
        activeGeneration = null
        generation.future.completeExceptionally(
            if (generation.cancelRequested || operation.releaseAfterLoad) {
                llmCancelledError(generation.identity.modelId, generation.requestId)
            } else {
                error.withRequestId(generation.requestId)
            },
        )
    }
    operation.releaseWaiters.forEach { it.complete(Unit) }
    operation.releaseWaiters.clear()
    if (closeRequested.get()) {
        finishClosed()
    }
}

internal fun LlmLifecycleActor.startGeneration(generation: LlmGenerationOperation) {
    val state = lifecycleState as? LlmLifecycleState.Ready
    val session = sessionManager.get(generation.identity.modelId)
    if (state?.identity != generation.identity || session == null) {
        activeGeneration = null
        generation.future.completeExceptionally(
            LlmRuntimeException(
                code = LlmRuntimeErrorCode.LOAD_FAILED,
                stage = LlmRuntimeStage.SESSION_LOAD,
                modelId = generation.identity.modelId,
                requestId = generation.requestId,
            ),
        )
        return
    }
    generation.session = session
    generation.epoch = state.epoch
    session.hasEnteredGenerationLifecycle = true
    lifecycleState = LlmLifecycleState.Generating(
        identity = generation.identity,
        epoch = state.epoch,
        requestId = generation.requestId,
    )
    try {
        nativeExecutor.execute {
            try {
                val result = session.backend.generate(
                    session = session,
                    prompt = generation.prompt,
                    maxTokens = generation.config.maxOutputTokens,
                    config = generation.config,
                )
                postLifecycle {
                    finishGeneration(generation, result, null)
                }
            } catch (error: Throwable) {
                postLifecycle {
                    finishGeneration(generation, null, error)
                }
            }
        }
    } catch (error: Throwable) {
        finishGeneration(generation, null, error)
    }
}

internal fun LlmLifecycleActor.finishGeneration(
    generation: LlmGenerationOperation,
    result: LocalLlmGenerateResult?,
    error: Throwable?,
) {
    val epoch = generation.epoch
    val state = lifecycleState
    val matchesState = when (state) {
        is LlmLifecycleState.Generating -> {
            state.requestId == generation.requestId && state.epoch == epoch
        }
        is LlmLifecycleState.Cancelling -> {
            state.requestId == generation.requestId && state.epoch == epoch
        }
        else -> false
    }
    if (
        activeGeneration !== generation ||
        epoch == null ||
        epoch != sessionEpoch ||
        !matchesState
    ) {
        return
    }
    activeGeneration = null
    val outcome = when {
        generation.cancelRequested -> Result.failure(
            llmCancelledError(generation.identity.modelId, generation.requestId),
        )
        error != null -> Result.failure(
            LlmRuntimeException.wrap(
                error = error,
                code = LlmRuntimeErrorCode.GENERATION_FAILED,
                stage = LlmRuntimeStage.GENERATION,
                modelId = generation.identity.modelId,
                requestId = generation.requestId,
            ),
        )
        else -> {
            val generated = requireNotNull(result)
            val session = requireNotNull(generation.session)
            Result.success(
                mapOf(
                    "text" to generated.text,
                    "finishReason" to generated.finishReason,
                    "usedPrivateContext" to generation.usedPrivateContext,
                    "status" to "ready",
                    "reason" to "本地 LLM runtime 已完成真实生成。",
                    "checkedAt" to System.currentTimeMillis(),
                    "modelPath" to generation.identity.canonicalModelPath,
                    "runtime" to session.backendName,
                    "actualBackend" to session.backendName,
                    "actualModel" to generation.identity.modelId,
                    "requestId" to generation.requestId,
                    "contextPackage" to packageName,
                ),
            )
        }
    }
    if (error == null && !generation.releaseRequested && !closeRequested.get()) {
        lifecycleState = LlmLifecycleState.Ready(generation.identity, epoch)
        completeLlmResult(generation.future, outcome)
        return
    }
    val waiters = generation.releaseWaiters.toList()
    generation.releaseWaiters.clear()
    startReleaseForCurrent(
        waiters = waiters,
        continuation = LlmReleaseContinuation(
            onSuccess = { completeLlmResult(generation.future, outcome) },
            onFailure = { completeLlmResult(generation.future, outcome) },
        ),
    )
}
