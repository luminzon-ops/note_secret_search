package com.example.note_secret_search

import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory

class LlmLifecycleCoordinator(
    packageName: String,
    sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    backendFactory: LlmBackendFactoryContract,
    private val runtimeBuildId: String = DEFAULT_LLM_RUNTIME_BUILD_ID,
    lifecycleExecutor: ExecutorService = Executors.newSingleThreadExecutor(
        llmDaemonThreadFactory("llm-lifecycle-actor"),
    ),
    nativeExecutor: ExecutorService = Executors.newSingleThreadExecutor(
        llmDaemonThreadFactory("llm-native-worker"),
    ),
    controlExecutor: ExecutorService = Executors.newSingleThreadExecutor(
        llmDaemonThreadFactory("llm-native-control"),
    ),
) : AutoCloseable {
    private val actor = LlmLifecycleActor(
        packageName = packageName,
        sessionManager = sessionManager,
        backendFactory = backendFactory,
        lifecycleExecutor = lifecycleExecutor,
        nativeExecutor = nativeExecutor,
        controlExecutor = controlExecutor,
    )

    fun snapshot(): LlmLifecycleSnapshot = actor.snapshot()

    fun inspectModel(
        modelId: String,
        modelPath: String,
    ): Map<String, Any?> = await(inspectModelAsync(modelId, modelPath))

    fun inspectModelAsync(
        modelId: String,
        modelPath: String,
    ): CompletableFuture<Map<String, Any?>> {
        if (modelId.isBlank() || modelPath.isBlank()) {
            return llmFailedFuture(
                LlmRuntimeException(
                    code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                    stage = LlmRuntimeStage.ARGUMENT,
                    modelId = modelId.takeIf { it.isNotBlank() },
                ),
            )
        }
        return CompletableFuture<Map<String, Any?>>().also { future ->
            actor.inspect(
                modelId = modelId,
                modelPath = modelPath,
                future = future,
            )
        }
    }

    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        verifiedChecksum: String? = null,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
    ): Map<String, Any?> = await(
        ensureModelReadyAsync(
            modelId = modelId,
            modelPath = modelPath,
            verifiedChecksum = verifiedChecksum,
            config = config,
        ),
    )

    fun ensureModelReadyAsync(
        modelId: String,
        modelPath: String,
        verifiedChecksum: String? = null,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
    ): CompletableFuture<Map<String, Any?>> {
        val identity = try {
            identityFor(modelId, modelPath, verifiedChecksum, config)
        } catch (error: Throwable) {
            return invalidFuture(error, modelId)
        }
        return CompletableFuture<Map<String, Any?>>().also { future ->
            actor.ensure(
                identity = identity,
                config = config,
                future = future,
            )
        }
    }

    fun generateText(
        modelId: String,
        modelPath: String,
        requestId: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
        verifiedChecksum: String? = null,
    ): Map<String, Any?> = await(
        generateTextAsync(
            modelId = modelId,
            modelPath = modelPath,
            requestId = requestId,
            prompt = prompt,
            usedPrivateContext = usedPrivateContext,
            config = config,
            verifiedChecksum = verifiedChecksum,
        ),
    )

    fun generateTextAsync(
        modelId: String,
        modelPath: String,
        requestId: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
        verifiedChecksum: String? = null,
    ): CompletableFuture<Map<String, Any?>> {
        if (requestId.isBlank() || prompt.isBlank()) {
            return llmFailedFuture(
                LlmRuntimeException(
                    code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                    stage = LlmRuntimeStage.ARGUMENT,
                    modelId = modelId.takeIf { it.isNotBlank() },
                    requestId = requestId.takeIf { it.isNotBlank() },
                ),
            )
        }
        val identity = try {
            identityFor(modelId, modelPath, verifiedChecksum, config)
        } catch (error: Throwable) {
            return invalidFuture(error, modelId, requestId)
        }
        return CompletableFuture<Map<String, Any?>>().also { future ->
            actor.generate(
                LlmGenerationOperation(
                    identity = identity,
                    requestId = requestId,
                    prompt = prompt.trim(),
                    usedPrivateContext = usedPrivateContext,
                    config = config,
                    future = future,
                ),
            )
        }
    }

    fun cancelGeneration(requestId: String): Boolean {
        return await(cancelGenerationAsync(requestId))
    }

    fun cancelGenerationAsync(requestId: String): CompletableFuture<Boolean> {
        if (requestId.isBlank()) {
            return llmFailedFuture(
                LlmRuntimeException(
                    code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                    stage = LlmRuntimeStage.ARGUMENT,
                ),
            )
        }
        return CompletableFuture<Boolean>().also { future ->
            actor.cancel(requestId, future)
        }
    }

    fun releaseModel(modelId: String) {
        await(releaseModelAsync(modelId))
    }

    fun releaseModelAsync(modelId: String): CompletableFuture<Unit> {
        if (modelId.isBlank()) {
            return llmFailedFuture(
                LlmRuntimeException(
                    code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                    stage = LlmRuntimeStage.ARGUMENT,
                ),
            )
        }
        return CompletableFuture<Unit>().also { future ->
            actor.release(modelId, future)
        }
    }

    fun closeAsync(): CompletableFuture<Unit> = actor.closeAsync()

    override fun close() {
        await(closeAsync())
    }

    private fun identityFor(
        modelId: String,
        modelPath: String,
        verifiedChecksum: String?,
        config: LocalLlmGenerationConfig,
    ): LlmSessionIdentity {
        require(modelId.isNotBlank()) { "modelId is required" }
        require(modelPath.isNotBlank()) { "modelPath is required" }
        require(config.contextLength > 0) { "contextLength must be positive" }
        require(config.maxOutputTokens > 0) { "maxOutputTokens must be positive" }
        require(config.maxPromptChars > 0) { "maxPromptChars must be positive" }
        return LlmSessionIdentity(
            modelId = modelId,
            canonicalModelPath = File(modelPath).canonicalPath,
            verifiedChecksum = verifiedChecksum
                ?.trim()
                ?.lowercase()
                ?.takeIf { it.isNotEmpty() },
            runtimeBuildId = runtimeBuildId,
            loadConfig = LlmLoadConfig(
                contextLength = config.contextLength,
                conservativeMode = config.conservativeMode,
            ),
        )
    }

    private fun <T> invalidFuture(
        error: Throwable,
        modelId: String?,
        requestId: String? = null,
    ): CompletableFuture<T> {
        return llmFailedFuture(
            LlmRuntimeException.wrap(
                error = error,
                code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                stage = LlmRuntimeStage.ARGUMENT,
                modelId = modelId,
                requestId = requestId,
            ),
        )
    }

    private fun <T> await(future: CompletableFuture<T>): T {
        return try {
            future.get()
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw LlmRuntimeException(
                code = LlmRuntimeErrorCode.CANCELLED,
                stage = LlmRuntimeStage.LIFECYCLE,
            )
        } catch (error: ExecutionException) {
            throw (error.cause ?: error)
        }
    }
}

internal fun llmDaemonThreadFactory(name: String): ThreadFactory {
    return ThreadFactory { runnable ->
        Thread(runnable, name).apply { isDaemon = true }
    }
}

internal fun <T> llmFailedFuture(error: LlmRuntimeException): CompletableFuture<T> {
    return CompletableFuture<T>().also { it.completeExceptionally(error) }
}
