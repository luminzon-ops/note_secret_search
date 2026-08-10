package com.example.note_secret_search

import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicBoolean

internal class LlmLifecycleActor(
    internal val packageName: String,
    internal val sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    internal val backendFactory: LlmBackendFactoryContract,
    internal val lifecycleExecutor: ExecutorService,
    internal val nativeExecutor: ExecutorService,
    internal val controlExecutor: ExecutorService,
) {
    @Volatile
    internal var lifecycleState: LlmLifecycleState = LlmLifecycleState.Empty

    @Volatile
    internal var sessionEpoch: Long = 0L

    internal val closeRequested = AtomicBoolean(false)
    internal var pendingLoad: LlmLoadOperation? = null
    internal var activeGeneration: LlmGenerationOperation? = null
    internal var releaseOperation: LlmReleaseOperation? = null
    internal var closeFuture: CompletableFuture<Unit>? = null
    internal var closeFailure: Throwable? = null

    fun snapshot(): LlmLifecycleSnapshot {
        val state = lifecycleState
        return LlmLifecycleSnapshot(
            state = state,
            sessionEpoch = sessionEpoch,
            activeRequestId = when (state) {
                is LlmLifecycleState.Generating -> state.requestId
                is LlmLifecycleState.Cancelling -> state.requestId
                else -> null
            },
        )
    }

    fun inspect(
        modelId: String,
        modelPath: String,
        future: CompletableFuture<Map<String, Any?>>,
    ) {
        postFor(future, modelId) {
            if (rejectClosed(future, modelId)) {
                return@postFor
            }
            try {
                val file = File(modelPath).canonicalFile
                if (!file.exists()) {
                    future.complete(
                        runtimeState(
                            status = "missing",
                            reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
                            modelPath = modelPath,
                            runtime = "none",
                        ),
                    )
                    return@postFor
                }
                val backend = backendFactory.create(file)
                val inspection = backend?.inspect(file)
                if (backend == null || inspection?.supported != true) {
                    future.complete(
                        runtimeState(
                            status = "degraded",
                            reason = inspection?.reason
                                ?: "当前模型格式暂无可用 Android 本地推理 backend。",
                            modelPath = modelPath,
                            runtime = "unsupported",
                        ),
                    )
                    return@postFor
                }
                val identity = currentLlmIdentity(lifecycleState)
                val activeSession = sessionManager.get(modelId)
                if (
                    identity?.canonicalModelPath == file.canonicalPath &&
                    activeSession != null
                ) {
                    future.complete(
                        runtimeState(
                            status = "ready",
                            reason = "本地 LLM runtime 已就绪。",
                            modelPath = modelPath,
                            runtime = activeSession.backendName,
                        ),
                    )
                } else {
                    future.complete(
                        runtimeState(
                            status = "installed_unverified",
                            reason = inspection.reason,
                            modelPath = modelPath,
                            runtime = "candidate",
                        ),
                    )
                }
            } catch (error: Throwable) {
                future.completeExceptionally(
                    LlmRuntimeException.wrap(
                        error = error,
                        code = LlmRuntimeErrorCode.LOAD_FAILED,
                        stage = LlmRuntimeStage.MODEL_LOOKUP,
                        modelId = modelId,
                    ),
                )
            }
        }
    }

    fun ensure(
        identity: LlmSessionIdentity,
        config: LocalLlmGenerationConfig,
        future: CompletableFuture<Map<String, Any?>>,
    ) {
        postFor(future, identity.modelId) {
            handleEnsure(identity, config, future)
        }
    }

    fun generate(operation: LlmGenerationOperation) {
        postFor(
            future = operation.future,
            modelId = operation.identity.modelId,
            requestId = operation.requestId,
        ) {
            handleGenerate(operation)
        }
    }

    fun cancel(requestId: String, future: CompletableFuture<Boolean>) {
        postFor(future, requestId = requestId) {
            val generation = activeGeneration
            if (generation == null || generation.requestId != requestId) {
                future.complete(false)
            } else {
                requestCancellation(generation)
                future.complete(true)
            }
        }
    }

    fun release(modelId: String, future: CompletableFuture<Unit>) {
        postFor(future, modelId) {
            handleRelease(modelId, future)
        }
    }

    fun closeAsync(): CompletableFuture<Unit> {
        synchronized(this) {
            closeFuture?.let { return it }
            val future = CompletableFuture<Unit>()
            closeFuture = future
            closeRequested.set(true)
            if (lifecycleState == LlmLifecycleState.Closed) {
                closeFailure?.let(future::completeExceptionally)
                    ?: future.complete(Unit)
                return future
            }
            postLifecycle(
                onFailure = future::completeExceptionally,
                block = ::handleClose,
            )
            return future
        }
    }

    internal fun handleEnsure(
        identity: LlmSessionIdentity,
        config: LocalLlmGenerationConfig,
        future: CompletableFuture<Map<String, Any?>>,
    ) {
        if (rejectClosed(future, identity.modelId)) {
            return
        }
        val file = File(identity.canonicalModelPath)
        if (!file.exists()) {
            future.complete(
                runtimeState(
                    status = "missing",
                    reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
                    modelPath = identity.canonicalModelPath,
                    runtime = "none",
                ),
            )
            return
        }
        when (val state = lifecycleState) {
            LlmLifecycleState.Empty -> startLoad(
                LlmLoadOperation(
                    identity = identity,
                    file = file,
                    config = config,
                    epoch = sessionEpoch + 1,
                    ensureWaiters = mutableListOf(future),
                ),
            )
            is LlmLifecycleState.Loading -> {
                val operation = pendingLoad
                if (state.identity == identity && operation != null) {
                    operation.ensureWaiters += future
                } else if (operation?.generation != null) {
                    queueReadinessSwitch(
                        generation = operation.generation!!,
                        identity = identity,
                        file = file,
                        config = config,
                        future = future,
                    )
                } else {
                    future.completeExceptionally(llmBusyError(identity.modelId))
                }
            }
            is LlmLifecycleState.Ready,
            is LlmLifecycleState.Generating,
            -> {
                if (currentLlmIdentity(state) == identity) {
                    future.complete(readyState(identity))
                } else if (state is LlmLifecycleState.Ready) {
                    switchTo(
                        identity = identity,
                        continuation = LlmReleaseContinuation(
                            onSuccess = {
                                startLoad(
                                    LlmLoadOperation(
                                        identity = identity,
                                        file = file,
                                        config = config,
                                        epoch = sessionEpoch + 1,
                                        ensureWaiters = mutableListOf(future),
                                    ),
                                )
                            },
                            onFailure = {
                                future.completeExceptionally(it.withModelId(identity.modelId))
                            },
                        ),
                    )
                } else {
                    val generation = activeGeneration
                    if (generation == null) {
                        future.completeExceptionally(llmBusyError(identity.modelId))
                    } else {
                        queueReadinessSwitch(
                            generation = generation,
                            identity = identity,
                            file = file,
                            config = config,
                            future = future,
                        )
                    }
                }
            }
            is LlmLifecycleState.Cancelling -> {
                val generation = activeGeneration
                if (generation == null || state.identity == identity) {
                    future.completeExceptionally(llmBusyError(identity.modelId))
                } else {
                    queueReadinessSwitch(
                        generation = generation,
                        identity = identity,
                        file = file,
                        config = config,
                        future = future,
                    )
                }
            }
            is LlmLifecycleState.Releasing,
            LlmLifecycleState.Closed,
            -> future.completeExceptionally(llmBusyError(identity.modelId))
        }
    }

    internal fun handleGenerate(generation: LlmGenerationOperation) {
        if (rejectClosed(generation.future, generation.identity.modelId, generation.requestId)) {
            return
        }
        if (activeGeneration != null) {
            generation.future.completeExceptionally(
                llmBusyError(generation.identity.modelId, generation.requestId),
            )
            return
        }
        activeGeneration = generation
        val identity = generation.identity
        val file = File(identity.canonicalModelPath)
        if (!file.exists()) {
            activeGeneration = null
            generation.future.completeExceptionally(
                LlmRuntimeException(
                    code = LlmRuntimeErrorCode.MODEL_MISSING,
                    stage = LlmRuntimeStage.MODEL_LOOKUP,
                    modelId = identity.modelId,
                    requestId = generation.requestId,
                ),
            )
            return
        }
        when (val state = lifecycleState) {
            LlmLifecycleState.Empty -> startLoad(
                LlmLoadOperation(
                    identity = identity,
                    file = file,
                    config = generation.config,
                    epoch = sessionEpoch + 1,
                    generation = generation,
                ),
            )
            is LlmLifecycleState.Loading -> {
                val operation = pendingLoad
                if (
                    state.identity == identity &&
                    operation != null &&
                    operation.generation == null
                ) {
                    operation.generation = generation
                } else {
                    activeGeneration = null
                    generation.future.completeExceptionally(
                        llmBusyError(identity.modelId, generation.requestId),
                    )
                }
            }
            is LlmLifecycleState.Ready -> {
                if (state.identity == identity) {
                    startGeneration(generation)
                } else {
                    switchTo(
                        identity = identity,
                        continuation = LlmReleaseContinuation(
                            onSuccess = {
                                startLoad(
                                    LlmLoadOperation(
                                        identity = identity,
                                        file = file,
                                        config = generation.config,
                                        epoch = sessionEpoch + 1,
                                        generation = generation,
                                    ),
                                )
                            },
                            onFailure = {
                                activeGeneration = null
                                generation.future.completeExceptionally(
                                    it.withModelId(identity.modelId)
                                        .withRequestId(generation.requestId),
                                )
                            },
                        ),
                    )
                }
            }
            is LlmLifecycleState.Generating,
            is LlmLifecycleState.Cancelling,
            is LlmLifecycleState.Releasing,
            LlmLifecycleState.Closed,
            -> {
                activeGeneration = null
                generation.future.completeExceptionally(
                    llmBusyError(identity.modelId, generation.requestId),
                )
            }
        }
    }

    internal fun postLifecycle(
        onFailure: (Throwable) -> Unit = ::recordActorFailure,
        block: () -> Unit,
    ) {
        try {
            lifecycleExecutor.execute {
                try {
                    block()
                } catch (error: Throwable) {
                    onFailure(error)
                }
            }
        } catch (error: Throwable) {
            onFailure(error)
        }
    }

    private fun queueReadinessSwitch(
        generation: LlmGenerationOperation,
        identity: LlmSessionIdentity,
        file: File,
        config: LocalLlmGenerationConfig,
        future: CompletableFuture<Map<String, Any?>>,
    ) {
        val queuedSwitch = generation.readinessSwitch
        when {
            queuedSwitch?.identity == identity -> {
                queuedSwitch.ensureWaiters += future
            }
            queuedSwitch != null -> {
                future.completeExceptionally(llmBusyError(identity.modelId))
            }
            else -> {
                generation.readinessSwitch = LlmLoadOperation(
                    identity = identity,
                    file = file,
                    config = config,
                    epoch = sessionEpoch + 1,
                    ensureWaiters = mutableListOf(future),
                )
                generation.releaseRequested = true
                requestCancellation(generation)
            }
        }
    }

    internal fun readyState(identity: LlmSessionIdentity): Map<String, Any?> {
        val session = sessionManager.get(identity.modelId)
        return runtimeState(
            status = "ready",
            reason = "本地 LLM runtime 已加载完成，可在首轮请求中执行真实生成。",
            modelPath = identity.canonicalModelPath,
            runtime = session?.backendName ?: "unknown",
        ) + mapOf(
            "actualBackend" to session?.backendName,
            "actualModel" to identity.modelId,
        )
    }

    internal fun runtimeState(
        status: String,
        reason: String,
        modelPath: String,
        runtime: String,
    ): Map<String, Any?> {
        return mapOf(
            "ready" to (status == "ready"),
            "status" to status,
            "reason" to reason,
            "checkedAt" to System.currentTimeMillis(),
            "modelPath" to modelPath,
            "runtime" to runtime,
            "supportsGeneration" to (status == "ready"),
            "contextPackage" to packageName,
        )
    }

    private fun <T> postFor(
        future: CompletableFuture<T>,
        modelId: String? = null,
        requestId: String? = null,
        block: () -> Unit,
    ) {
        postLifecycle(
            onFailure = { error ->
                future.completeExceptionally(
                    if (
                        closeRequested.get() ||
                        lifecycleState == LlmLifecycleState.Closed
                    ) {
                        llmClosedError(modelId, requestId)
                    } else {
                        LlmRuntimeException.wrap(
                            error = error,
                            code = LlmRuntimeErrorCode.GENERATION_FAILED,
                            stage = LlmRuntimeStage.LIFECYCLE,
                            modelId = modelId,
                            requestId = requestId,
                        )
                    },
                )
            },
            block = block,
        )
    }

    private fun <T> rejectClosed(
        future: CompletableFuture<T>,
        modelId: String? = null,
        requestId: String? = null,
    ): Boolean {
        if (!closeRequested.get() && lifecycleState != LlmLifecycleState.Closed) {
            return false
        }
        future.completeExceptionally(llmClosedError(modelId, requestId))
        return true
    }

    private fun recordActorFailure(error: Throwable) {
        closeFailure = closeFailure ?: error
        closeFuture?.completeExceptionally(error)
    }
}
