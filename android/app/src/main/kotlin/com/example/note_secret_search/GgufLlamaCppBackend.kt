package com.example.note_secret_search

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume

class GgufLlamaCppBackend internal constructor(
    private val client: LlamaContextClient,
    private val predictionScope: CoroutineScope,
    private val eventFlow: MutableSharedFlow<LlamaRuntimeEvent>,
) : LocalLlmBackend {
    constructor(context: Context) : this(createRuntimeComponents(context))

    private constructor(components: RuntimeComponents) : this(
        client = components.client,
        predictionScope = components.predictionScope,
        eventFlow = components.eventFlow,
    )

    private val releaseCoordinator = PredictionReleaseCoordinator(
        abortPrediction = { client.abort() },
        releaseResources = {
            client.release()
            predictionScope.cancel()
        },
    )
    private val nextGenerationId = AtomicLong(1L)

    override fun inspect(file: File): LocalLlmInspectResult {
        if (!file.exists()) {
            return LocalLlmInspectResult(
                supported = false,
                reason = "模型文件不存在。",
            )
        }

        return if (file.extension.lowercase() == "gguf") {
            LocalLlmInspectResult(
                supported = true,
                reason = "检测到 GGUF 模型文件，可继续进行 runtime 校验。",
            )
        } else {
            LocalLlmInspectResult(
                supported = false,
                reason = "当前仅支持 GGUF 模型文件。",
            )
        }
    }

    override fun load(modelId: String, file: File): LocalLlmBackendSession {
        return load(
            modelId = modelId,
            file = file,
            config = LocalLlmGenerationConfig(),
        )
    }

    override fun load(
        modelId: String,
        file: File,
        config: LocalLlmGenerationConfig,
    ): LocalLlmBackendSession {
        val contextId = runBlocking {
            awaitLoadedContextId(
                timeoutMillis = LLM_MODEL_LOAD_TIMEOUT_MS,
                loadScope = predictionScope,
                startOnCallerThread = true,
                onLateLoaded = {
                    client.release()
                },
            ) { onLoaded ->
                client.load(
                    file = file,
                    contextLength = config.contextLength,
                    onLoaded = onLoaded,
                )
            }
        }

        return LocalLlmBackendSession(
            modelId = modelId,
            modelPath = file.absolutePath,
            backendName = "gguf-llama-cpp",
            handle = contextId,
            backend = this,
        )
    }

    override fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ): LocalLlmGenerateResult {
        require(prompt.isNotBlank()) { "Prompt must not be blank." }
        val normalizedPrompt = prompt.trim()
        val promptLimit = minOf(
            config.maxPromptChars,
            LOCAL_LLM_MAX_PROMPT_CHARS,
        )
        require(normalizedPrompt.length <= promptLimit) {
            "Prompt exceeds maxPromptChars."
        }
        val generationId = nextGenerationId.getAndIncrement()

        return runBlocking {
            val event = awaitPredictionTerminalEvent(
                timeoutMillis = LLM_PREDICTION_TIMEOUT_MS,
                timeoutCleanupMillis = LLM_PREDICTION_TIMEOUT_CLEANUP_MS,
                predictionScope = predictionScope,
                events = eventFlow,
                isTerminal = { candidate ->
                    candidate.generationId == generationId &&
                        (
                            candidate is LlamaRuntimeEvent.Done ||
                                candidate is LlamaRuntimeEvent.Error
                            )
                },
                onTimeout = {
                    releaseCoordinator.abortPrediction()
                },
                tryRegisterPrediction = {
                    releaseCoordinator.tryRegisterPrediction()
                },
                onPredictionFinished = {
                    releaseCoordinator.onPredictionFinished()
                },
                startOnCallerThread = true,
            ) {
                client.predict(
                    prompt = normalizedPrompt,
                    emitPartialCompletion = false,
                    maxTokens = config.maxOutputTokens,
                    config = config,
                    generationId = generationId,
                )
            }

            when (event) {
                is LlamaRuntimeEvent.Done -> {
                    val text = event.text.trim()
                    require(text.isNotBlank()) { "Backend returned empty text." }
                    LocalLlmGenerateResult(
                        text = text,
                        finishReason = "stop",
                    )
                }

                is LlamaRuntimeEvent.Error -> {
                    throw IllegalStateException(event.message)
                }

                else -> throw IllegalStateException(
                    "Unexpected local LLM event.",
                )
            }
        }
    }

    override fun release(session: LocalLlmBackendSession) {
        releaseCoordinator.requestRelease()
    }

    override fun cancel(session: LocalLlmBackendSession) {
        client.abort()
    }
}

private data class RuntimeComponents(
    val client: LlamaContextClient,
    val predictionScope: CoroutineScope,
    val eventFlow: MutableSharedFlow<LlamaRuntimeEvent>,
)

private fun createRuntimeComponents(context: Context): RuntimeComponents {
    val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val eventFlow = MutableSharedFlow<LlamaRuntimeEvent>(
        replay = 0,
        extraBufferCapacity = 64,
    )
    return RuntimeComponents(
        client = DirectLlamaContextClient(
            context = context,
            events = eventFlow,
        ),
        predictionScope = predictionScope,
        eventFlow = eventFlow,
    )
}

internal const val LLM_MODEL_LOAD_TIMEOUT_MS = 30_000L
internal const val LLM_PREDICTION_TIMEOUT_MS = 45_000L
internal const val LLM_PREDICTION_TIMEOUT_CLEANUP_MS = 5_000L
internal const val HUAWEI_SAFE_CONTEXT_LENGTH = 1024

internal class PredictionReleaseCoordinator(
    private val abortPrediction: () -> Unit,
    private val releaseResources: () -> Unit,
) {
    private val lock = Any()
    private var inFlightPredictionCount = 0
    private var releaseRequested = false
    private var abortCompleted = false
    private var released = false
    private val releaseCompletion = CompletableFuture<Unit>()

    fun tryRegisterPrediction(): Boolean = synchronized(lock) {
        if (releaseRequested || released) {
            false
        } else {
            inFlightPredictionCount += 1
            true
        }
    }

    fun onPredictionFinished() {
        val shouldRelease = synchronized(lock) {
            if (inFlightPredictionCount > 0) {
                inFlightPredictionCount -= 1
            }
            markReleasedIfReady()
        }
        if (shouldRelease) {
            completeRelease()
        }
    }

    fun abortPrediction() {
        abortPrediction.invoke()
    }

    fun requestRelease() {
        val shouldAbort = synchronized(lock) {
            if (releaseRequested) {
                false
            } else {
                releaseRequested = true
                true
            }
        }
        if (shouldAbort) {
            try {
                abortPrediction.invoke()
            } finally {
                val shouldRelease = synchronized(lock) {
                    abortCompleted = true
                    markReleasedIfReady()
                }
                if (shouldRelease) {
                    completeRelease()
                }
            }
        }
        try {
            releaseCompletion.get()
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            throw error
        } catch (error: ExecutionException) {
            throw (error.cause ?: error)
        }
    }

    private fun completeRelease() {
        try {
            releaseResources.invoke()
            releaseCompletion.complete(Unit)
        } catch (error: Throwable) {
            releaseCompletion.completeExceptionally(error)
        }
    }

    private fun markReleasedIfReady(): Boolean {
        if (
            releaseRequested &&
            abortCompleted &&
            inFlightPredictionCount == 0 &&
            !released
        ) {
            released = true
            return true
        }
        return false
    }
}

internal suspend fun awaitLoadedContextId(
    timeoutMillis: Long,
    loadScope: CoroutineScope,
    startOnCallerThread: Boolean = false,
    onLateLoaded: () -> Unit,
    startLoad: (((Long) -> Unit)) -> Unit,
): Long = withTimeout(timeoutMillis) {
    suspendCancellableCoroutine { continuation ->
        val completionState = AtomicInteger(0)
        val cleanupRequested = AtomicBoolean(false)
        val cleanupLateLoad = {
            if (cleanupRequested.compareAndSet(false, true)) {
                try {
                    onLateLoaded()
                } catch (_: Throwable) {
                }
            }
        }
        continuation.invokeOnCancellation {
            if (completionState.get() == 1) {
                cleanupLateLoad()
            }
        }
        val load = {
            try {
                startLoad { contextId ->
                    if (completionState.compareAndSet(0, 1)) {
                        if (continuation.isCancelled) {
                            cleanupLateLoad()
                        } else {
                            continuation.resume(contextId)
                        }
                    }
                }
            } catch (error: Throwable) {
                if (completionState.compareAndSet(0, 2)) {
                    continuation.resumeWith(Result.failure(error))
                }
            }
        }
        if (startOnCallerThread) {
            load()
        } else {
            loadScope.launch { load() }
        }
    }
}

internal suspend fun <T> awaitPredictionTerminalEvent(
    timeoutMillis: Long,
    timeoutCleanupMillis: Long,
    predictionScope: CoroutineScope,
    events: Flow<T>,
    isTerminal: (T) -> Boolean,
    onEvent: (T) -> Unit = {},
    onTimeout: () -> Unit,
    tryRegisterPrediction: () -> Boolean,
    onPredictionFinished: () -> Unit,
    startOnCallerThread: Boolean = false,
    startPrediction: () -> Unit,
): T = coroutineScope {
    val terminal = async(start = CoroutineStart.UNDISPATCHED) {
        events.first { candidate ->
            onEvent(candidate)
            isTerminal(candidate)
        }
    }
    if (!tryRegisterPrediction()) {
        terminal.cancel()
        throw IllegalStateException("Local LLM backend is releasing.")
    }

    val predictionFailure = CompletableDeferred<Throwable>()
    val predictionCompletion = CompletableDeferred<Unit>()
    val timeoutTriggered = AtomicBoolean(false)
    val timeoutCompleted = CompletableDeferred<Unit>()
    val timeoutJob = predictionScope.launch {
        delay(timeoutMillis)
        if (timeoutTriggered.compareAndSet(false, true)) {
            try {
                onTimeout()
            } catch (_: Throwable) {
            } finally {
                timeoutCompleted.complete(Unit)
            }
        }
    }
    val runPrediction = {
        try {
            startPrediction()
        } catch (error: Throwable) {
            predictionFailure.complete(error)
        } finally {
            onPredictionFinished()
            predictionCompletion.complete(Unit)
        }
    }
    val predictionJob = if (startOnCallerThread) {
        runPrediction()
        null
    } else {
        predictionScope.launch { runPrediction() }
    }

    try {
        withTimeout(timeoutMillis + timeoutCleanupMillis + 1_000L) {
            select<T> {
                terminal.onAwait { event ->
                    if (timeoutTriggered.get()) {
                        throwTimeoutCancellation()
                    }
                    event
                }
                predictionFailure.onAwait { error ->
                    if (timeoutTriggered.get()) {
                        throwTimeoutCancellation()
                    }
                    throw error
                }
                timeoutCompleted.onAwait {
                    throwTimeoutCancellation()
                }
            }
        }
    } catch (error: TimeoutCancellationException) {
        if (timeoutTriggered.compareAndSet(false, true)) {
            try {
                onTimeout()
            } catch (_: Throwable) {
            } finally {
                timeoutCompleted.complete(Unit)
            }
        } else {
            timeoutCompleted.await()
        }
        withTimeoutOrNull(timeoutCleanupMillis) {
            predictionCompletion.await()
        }
        throw error
    } finally {
        timeoutJob.cancel()
        predictionJob?.cancel()
        terminal.cancel()
    }
}

private suspend fun throwTimeoutCancellation(): Nothing {
    return withTimeout(1L) {
        CompletableDeferred<Nothing>().await()
    }
}
