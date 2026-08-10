package com.example.note_secret_search

import android.content.Context
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicLong

interface LocalLlmRuntimeContract : AutoCloseable {
    fun inspectModel(modelId: String, modelPath: String): Map<String, Any?>

    fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?>

    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        return ensureModelReady(modelId, modelPath)
    }

    fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
    ): Map<String, Any?>

    fun generateText(
        modelId: String,
        modelPath: String,
        requestId: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
        verifiedChecksum: String? = null,
    ): Map<String, Any?> {
        return generateText(
            modelId = modelId,
            modelPath = modelPath,
            prompt = prompt,
            usedPrivateContext = usedPrivateContext,
            config = config,
        )
    }

    fun cancelGeneration(requestId: String): Boolean = false

    fun releaseModel(modelId: String)

    fun closeAsync(): CompletableFuture<Unit> {
        return try {
            close()
            CompletableFuture.completedFuture(Unit)
        } catch (error: Throwable) {
            CompletableFuture<Unit>().also { it.completeExceptionally(error) }
        }
    }

    override fun close() {
    }
}

class LocalLlmRuntime(
    packageName: String,
    sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    backendFactory: LlmBackendFactoryContract,
    private val lifecycle: LlmLifecycleCoordinator = LlmLifecycleCoordinator(
        packageName = packageName,
        sessionManager = sessionManager,
        backendFactory = backendFactory,
    ),
) : LocalLlmRuntimeContract {
    constructor(
        context: Context,
        sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    ) : this(
        packageName = context.packageName,
        sessionManager = sessionManager,
        backendFactory = LlmBackendFactory(context),
    )

    override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
        return lifecycle.inspectModel(modelId, modelPath)
    }

    override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
        return lifecycle.ensureModelReady(
            modelId = modelId,
            modelPath = modelPath,
        )
    }

    override fun ensureModelReady(
        modelId: String,
        modelPath: String,
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        return lifecycle.ensureModelReady(
            modelId = modelId,
            modelPath = modelPath,
            verifiedChecksum = verifiedChecksum,
        )
    }

    override fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
    ): Map<String, Any?> {
        return try {
            generateText(
                modelId = modelId,
                modelPath = modelPath,
                requestId = "legacy-${LEGACY_REQUEST_SEQUENCE.incrementAndGet()}",
                prompt = prompt,
                usedPrivateContext = usedPrivateContext,
                config = config,
            )
        } catch (error: LlmRuntimeException) {
            if (
                error.code == LlmRuntimeErrorCode.GENERATION_FAILED ||
                error.code == LlmRuntimeErrorCode.LOAD_FAILED
            ) {
                throw IllegalStateException("Local LLM generation failed.", error)
            }
            throw error
        }
    }

    override fun generateText(
        modelId: String,
        modelPath: String,
        requestId: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        return lifecycle.generateText(
            modelId = modelId,
            modelPath = modelPath,
            requestId = requestId,
            prompt = prompt,
            usedPrivateContext = usedPrivateContext,
            config = config,
            verifiedChecksum = verifiedChecksum,
        )
    }

    override fun cancelGeneration(requestId: String): Boolean {
        return lifecycle.cancelGeneration(requestId)
    }

    override fun releaseModel(modelId: String) {
        lifecycle.releaseModel(modelId)
    }

    override fun closeAsync(): CompletableFuture<Unit> = lifecycle.closeAsync()

    override fun close() {
        lifecycle.close()
    }

    companion object {
        private val LEGACY_REQUEST_SEQUENCE = AtomicLong(0)
    }
}
