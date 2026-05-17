package com.example.note_secret_search

import android.content.Context
import android.util.Log
import org.nehuatl.llamacpp.LlamaHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.selects.select
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume

class GgufLlamaCppBackend internal constructor(
    private val helper: LlamaHelperClient,
    private val predictionScope: CoroutineScope,
    private val eventFlow: MutableSharedFlow<LlamaHelper.LLMEvent>,
) : LocalLlmBackend {
    constructor(context: Context) : this(createRuntimeComponents(context))

    private constructor(components: RuntimeComponents) : this(
        helper = components.helper,
        predictionScope = components.predictionScope,
        eventFlow = components.eventFlow,
    )

    private val releaseCoordinator = PredictionReleaseCoordinator(
        abortPrediction = { helper.abort() },
        releaseResources = {
            helper.release()
            predictionScope.cancel()
        },
    )

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
        val modelPath = normalizeModelPathForLlama(file)
        val contextId = runBlocking {
            awaitLoadedContextId(timeoutMillis = LLM_MODEL_LOAD_TIMEOUT_MS) { onLoaded ->
                helper.load(
                    path = modelPath,
                    contextLength = HUAWEI_SAFE_CONTEXT_LENGTH,
                ) { id ->
                    onLoaded(id)
                }
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
        val boundedPrompt = prompt.trim().take(config.maxPromptChars)
        val requestStartedAtMs = System.currentTimeMillis()
        logBackendInfo(
            "generate enter modelId=${session.modelId} promptChars=${boundedPrompt.length} " +
                "maxOutputTokens=${config.maxOutputTokens} contextLength=${config.contextLength} " +
                "timeoutMs=$LLM_PREDICTION_TIMEOUT_MS",
        )

        return runBlocking {
            var latestOngoingText = ""
            val heartbeatJob = launch(Dispatchers.IO) {
                var beat = 1
                while (true) {
                    delay(HEARTBEAT_INTERVAL_MS)
                    val elapsed = System.currentTimeMillis() - requestStartedAtMs
                    logBackendInfo(
                        "generate heartbeat beat=$beat elapsedMs=$elapsed modelId=${session.modelId} " +
                            "ongoingChars=${latestOngoingText.length}",
                    )
                    beat += 1
                }
            }

            val event = try {
                awaitPredictionTerminalEvent(
                    timeoutMillis = LLM_PREDICTION_TIMEOUT_MS,
                    timeoutCleanupMillis = LLM_PREDICTION_TIMEOUT_CLEANUP_MS,
                    predictionScope = predictionScope,
                    events = eventFlow,
                    isTerminal = { candidate ->
                        candidate is LlamaHelper.LLMEvent.Done || candidate is LlamaHelper.LLMEvent.Error
                    },
                    onEvent = { candidate ->
                        if (candidate is LlamaHelper.LLMEvent.Ongoing) {
                            latestOngoingText = candidate.word.trim()
                        }
                    },
                    onTimeout = {
                        logBackendWarn(
                            "generate timeout modelId=${session.modelId} " +
                                "elapsedMs=${System.currentTimeMillis() - requestStartedAtMs} " +
                                "ongoingChars=${latestOngoingText.length}",
                        )
                        releaseCoordinator.abortPrediction()
                    },
                    onPredictionStarted = {
                        releaseCoordinator.onPredictionStarted()
                    },
                    onPredictionFinished = {
                        releaseCoordinator.onPredictionFinished()
                    },
                ) {
                    helper.predict(
                        prompt = boundedPrompt,
                        emitPartialCompletion = config.emitPartialCompletion,
                        maxTokens = config.maxOutputTokens,
                        config = config,
                    )
                }
            } finally {
                heartbeatJob.cancel()
            }

            val elapsedMs = System.currentTimeMillis() - requestStartedAtMs
            when (event) {
                is LlamaHelper.LLMEvent.Done -> {
                    val text = event.fullText.trim().ifEmpty { latestOngoingText }
                    logBackendInfo(
                        "generate done modelId=${session.modelId} elapsedMs=$elapsedMs " +
                            "responseChars=${text.length}",
                    )
                    require(text.isNotBlank()) { "Backend returned empty text." }
                    LocalLlmGenerateResult(
                        text = text,
                        finishReason = "stop",
                    )
                }

                is LlamaHelper.LLMEvent.Error -> {
                    logBackendWarn(
                        "generate error modelId=${session.modelId} elapsedMs=$elapsedMs message=${event.message}",
                    )
                    throw IllegalStateException(event.message)
                }

                else -> throw IllegalStateException("Unexpected llama helper event.")
            }
        }
    }

    override fun release(session: LocalLlmBackendSession) {
        releaseCoordinator.requestRelease()
    }
}

internal interface LlamaHelperClient {
    fun load(path: String, contextLength: Int, onLoaded: (Long) -> Unit)

    fun predict(
        prompt: String,
        emitPartialCompletion: Boolean,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    )

    fun abort()

    fun release()
}

internal class AndroidLlamaHelperClient(
    context: Context,
    scope: CoroutineScope,
    private val sharedFlow: MutableSharedFlow<LlamaHelper.LLMEvent>,
) : LlamaHelperClient {
    private val llamaHelper = LlamaHelper(
        contentResolver = context.contentResolver,
        scope = scope,
        sharedFlow = sharedFlow,
    )

    private val predictionScope: CoroutineScope = scope

    override fun load(path: String, contextLength: Int, onLoaded: (Long) -> Unit) {
        llamaHelper.load(path, contextLength, onLoaded)
    }

    override fun predict(
        prompt: String,
        emitPartialCompletion: Boolean,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ) {
        // Bypass LlamaHelper.predict which does NOT pass n_predict to native — the AAR's
        // default unbounded prediction loops forever on Huawei Kirin 990. We call
        // LlamaAndroid.launchCompletion(contextId, params) directly with an explicit
        // n_predict cap and sampling params from the caller-provided config.
        // We also register setTokenCallback before calling launchCompletion so that
        // partial tokens flow through sharedFlow when emit_partial_completion is enabled.
        val helperContextId = readContextIdReflectively()
        if (helperContextId == null) {
            llamaHelper.predict(prompt, emitPartialCompletion)
            return
        }

        val llamaAndroid = readLlamaAndroidReflectively()
        if (llamaAndroid == null) {
            llamaHelper.predict(prompt, emitPartialCompletion)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val contexts = readContextsReflectively(llamaAndroid)
            as? java.util.concurrent.ConcurrentHashMap<Int, org.nehuatl.llamacpp.LlamaContext>
        contexts?.get(helperContextId)?.setTokenCallback { token ->
            sharedFlow.tryEmit(LlamaHelper.LLMEvent.Ongoing(token, 0))
        }

        predictionScope.launch {
            val params = mutableMapOf<String, Any>(
                "prompt" to prompt,
                "emit_partial_completion" to emitPartialCompletion,
                "n_predict" to maxTokens,
                "temperature" to config.temperature,
                "top_k" to config.topK,
                "top_p" to config.topP,
                "seed" to config.seed,
                "stop" to config.stopSequences,
            )
            try {
                @Suppress("UNCHECKED_CAST")
                val result = llamaAndroid.launchCompletion(helperContextId, params) as? Map<String, Any?>
                val text = (result?.get("text") as? String).orEmpty()
                sharedFlow.tryEmit(LlamaHelper.LLMEvent.Done(text, 0, 0L))
            } catch (error: Throwable) {
                sharedFlow.tryEmit(LlamaHelper.LLMEvent.Error(error.message ?: "completion failed"))
            }
        }
    }

    override fun abort() {
        llamaHelper.abort()
    }

    override fun release() {
        llamaHelper.release()
    }

    private fun readContextIdReflectively(): Int? {
        return try {
            val accessor = LlamaHelper::class.java.getDeclaredMethod(
                "access\$getCurrentContext\$p",
                LlamaHelper::class.java,
            )
            (accessor.invoke(null, llamaHelper) as? Number)?.toInt()
        } catch (_: Throwable) {
            null
        }
    }

    private fun readLlamaAndroidReflectively(): org.nehuatl.llamacpp.LlamaAndroid? {
        return try {
            val accessor = LlamaHelper::class.java.getDeclaredMethod(
                "access\$getLlama",
                LlamaHelper::class.java,
            )
            accessor.invoke(null, llamaHelper) as? org.nehuatl.llamacpp.LlamaAndroid
        } catch (_: Throwable) {
            null
        }
    }

    private fun readContextsReflectively(llamaAndroid: org.nehuatl.llamacpp.LlamaAndroid): Any? {
        return try {
            val accessor = org.nehuatl.llamacpp.LlamaAndroid::class.java.getDeclaredMethod(
                "access\$getContexts\$p",
                org.nehuatl.llamacpp.LlamaAndroid::class.java,
            )
            accessor.invoke(null, llamaAndroid)
        } catch (_: Throwable) {
            null
        }
    }
}

private data class RuntimeComponents(
    val helper: LlamaHelperClient,
    val predictionScope: CoroutineScope,
    val eventFlow: MutableSharedFlow<LlamaHelper.LLMEvent>,
)

private fun createRuntimeComponents(context: Context): RuntimeComponents {
    val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val eventFlow = MutableSharedFlow<LlamaHelper.LLMEvent>(
        replay = 0,
        extraBufferCapacity = 64,
    )
    return RuntimeComponents(
        helper = AndroidLlamaHelperClient(
            context = context,
            scope = predictionScope,
            sharedFlow = eventFlow,
        ),
        predictionScope = predictionScope,
        eventFlow = eventFlow,
    )
}

internal const val LLM_MODEL_LOAD_TIMEOUT_MS = 30_000L
internal const val LLM_PREDICTION_TIMEOUT_MS = 45_000L
internal const val LLM_PREDICTION_TIMEOUT_CLEANUP_MS = 5_000L
internal const val HUAWEI_SAFE_CONTEXT_LENGTH = 1024
private const val BACKEND_TAG = "GgufLlamaCppBackend"
private const val HEARTBEAT_INTERVAL_MS = 5_000L

private fun logBackendInfo(message: String) {
    try {
        Log.i(BACKEND_TAG, message)
    } catch (_: RuntimeException) {
    }
}

private fun logBackendWarn(message: String) {
    try {
        Log.w(BACKEND_TAG, message)
    } catch (_: RuntimeException) {
    }
}

internal class PredictionReleaseCoordinator(
    private val abortPrediction: () -> Unit,
    private val releaseResources: () -> Unit,
) {
    private val inFlightPredictionCount = AtomicInteger(0)
    private val releaseRequested = AtomicBoolean(false)
    private val released = AtomicBoolean(false)

    fun onPredictionStarted() {
        inFlightPredictionCount.incrementAndGet()
    }

    fun onPredictionFinished() {
        val remaining = inFlightPredictionCount.updateAndGet { current ->
            if (current <= 0) 0 else current - 1
        }
        if (remaining == 0 && releaseRequested.get()) {
            releaseNowIfNeeded()
        }
    }

    fun abortPrediction() {
        abortPrediction.invoke()
    }

    fun requestRelease() {
        releaseRequested.set(true)
        abortPrediction.invoke()
        if (inFlightPredictionCount.get() == 0) {
            releaseNowIfNeeded()
        }
    }

    private fun releaseNowIfNeeded() {
        if (released.compareAndSet(false, true)) {
            releaseResources.invoke()
        }
    }
}

internal fun normalizeModelPathForLlama(file: File): String = file.toURI().toString()

internal suspend fun awaitLoadedContextId(
    timeoutMillis: Long,
    startLoad: (((Long) -> Unit)) -> Unit,
): Long = withTimeout(timeoutMillis) {
    suspendCancellableCoroutine { continuation ->
        startLoad { contextId ->
            if (continuation.isActive) {
                continuation.resume(contextId)
            }
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
    onPredictionStarted: () -> Unit,
    onPredictionFinished: () -> Unit,
    startPrediction: () -> Unit,
): T = coroutineScope {
    coroutineScope {
        val terminal = async(start = CoroutineStart.UNDISPATCHED) {
            events.first { candidate ->
                onEvent(candidate)
                isTerminal(candidate)
            }
        }
        val predictionFailure = CompletableDeferred<Throwable>()
        val predictionCompletion = CompletableDeferred<Unit>()
        val predictionJob = predictionScope.launch {
            onPredictionStarted()
            try {
                startPrediction()
            } catch (error: Throwable) {
                predictionFailure.complete(error)
            } finally {
                onPredictionFinished()
                predictionCompletion.complete(Unit)
            }
        }

        try {
            withTimeout(timeoutMillis) {
                select<T> {
                    terminal.onAwait { event -> event }
                    predictionFailure.onAwait { error ->
                        throw error
                    }
                }
            }
        } catch (error: TimeoutCancellationException) {
            onTimeout()
            withTimeoutOrNull(timeoutCleanupMillis) {
                predictionCompletion.await()
            }
            throw error
        } finally {
            predictionJob.cancel()
            terminal.cancel()
        }
    }
}
