package com.example.note_secret_search

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class LlmRuntimePlugin(
    context: Context? = null,
    private val runtime: LocalLlmRuntimeContract = LocalLlmRuntime(
        context = requireNotNull(context) { "context is required when runtime is not provided" },
        sessionManager = LlmModelSessionManager(),
    ),
    private val multimodalRuntime: MultimodalLlmRuntimeContract = FallbackMultimodalLlmRuntime(),
    workerExecutor: Executor? = null,
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
) : MethodChannel.MethodCallHandler {
    private val attachmentLock = Any()
    private val ownsWorkerExecutor = workerExecutor == null
    private val workerExecutor: Executor = workerExecutor ?: Executors.newFixedThreadPool(3) { runnable ->
        Thread(runnable, "llm-method-channel-worker").apply { isDaemon = true }
    }
    private val cancellationExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "llm-method-channel-control").apply { isDaemon = true }
    }
    private var channel: MethodChannel? = null
    private var attachmentEpoch = 0L
    private var callbacksEnabled = true
    private var detachFuture: CompletableFuture<Unit>? = null

    fun attachToEngine(messenger: BinaryMessenger) {
        synchronized(attachmentLock) {
            check(detachFuture == null) { "Local LLM runtime is closed." }
            channel?.setMethodCallHandler(null)
            attachmentEpoch += 1
            callbacksEnabled = true
            channel = MethodChannel(messenger, CHANNEL_NAME).also {
                it.setMethodCallHandler(this)
            }
        }
    }

    fun detachFromEngine(): CompletableFuture<Unit> {
        synchronized(attachmentLock) {
            detachFuture?.let { return it }
            callbacksEnabled = false
            attachmentEpoch += 1
            channel?.setMethodCallHandler(null)
            channel = null
            val closing = try {
                runtime.closeAsync()
            } catch (error: Throwable) {
                CompletableFuture<Unit>().also { it.completeExceptionally(error) }
            }
            detachFuture = closing
            if (ownsWorkerExecutor) {
                closing.whenComplete { _, _ ->
                    (workerExecutor as? ExecutorService)?.shutdown()
                }
            }
            closing.whenComplete { _, _ -> cancellationExecutor.shutdown() }
            return closing
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val callback = OneShotMethodResult(
            delegate = result,
            dispatcher = resultDispatcher,
            attachmentEpoch = currentAttachmentEpoch(),
            deliverIfCurrent = ::deliverIfCurrent,
        )
        try {
            when (call.method) {
                "inspectModel" -> inspectModel(call, callback)
                "ensureModelReady" -> ensureModelReady(call, callback)
                "generateText" -> generateText(call, callback)
                "cancelGeneration",
                "cancelRequest",
                -> cancelGeneration(call, callback)
                "releaseModel" -> releaseModel(call, callback)
                "ensureMultimodalModelReady",
                "generateMultimodalText",
                -> callback.error(
                    code = "UNSUPPORTED_CAPABILITY",
                    message = "UNSUPPORTED_CAPABILITY",
                    details = null,
                )
                else -> callback.notImplemented()
            }
        } catch (error: Throwable) {
            callback.failure(
                error = error,
                fallbackCode = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                stage = LlmRuntimeStage.ARGUMENT,
            )
        }
    }

    private fun inspectModel(call: MethodCall, callback: OneShotMethodResult) {
        val modelId = requiredString(call, "modelId")
        val modelPath = requiredString(call, "modelPath")
        runAsync(
            callback = callback,
            fallbackCode = LlmRuntimeErrorCode.LOAD_FAILED,
            stage = LlmRuntimeStage.MODEL_LOOKUP,
            modelId = modelId,
        ) {
            runtime.inspectModel(modelId = modelId, modelPath = modelPath)
        }
    }

    private fun ensureModelReady(call: MethodCall, callback: OneShotMethodResult) {
        val modelId = requiredString(call, "modelId")
        val modelPath = requiredString(call, "modelPath")
        val verifiedChecksum = optionalNonBlankString(call, "verifiedChecksum")
        runAsync(
            callback = callback,
            fallbackCode = LlmRuntimeErrorCode.LOAD_FAILED,
            stage = LlmRuntimeStage.SESSION_LOAD,
            modelId = modelId,
        ) {
            runtime.ensureModelReady(
                modelId = modelId,
                modelPath = modelPath,
                verifiedChecksum = verifiedChecksum,
            )
        }
    }

    private fun generateText(call: MethodCall, callback: OneShotMethodResult) {
        val modelId = requiredString(call, "modelId")
        val modelPath = requiredString(call, "modelPath")
        val requestId = requestId(call)
        val prompt = requiredString(call, "prompt")
        val usedPrivateContext = call.argument<Boolean>("usedPrivateContext") ?: false
        val verifiedChecksum = optionalNonBlankString(call, "verifiedChecksum")
        val config = readGenerationConfig(call)
        runAsync(
            callback = callback,
            fallbackCode = LlmRuntimeErrorCode.GENERATION_FAILED,
            stage = LlmRuntimeStage.GENERATION,
            modelId = modelId,
            requestId = requestId,
        ) {
            runtime.generateText(
                modelId = modelId,
                modelPath = modelPath,
                requestId = requestId,
                prompt = prompt,
                usedPrivateContext = usedPrivateContext,
                config = config,
                verifiedChecksum = verifiedChecksum,
            )
        }
    }

    private fun cancelGeneration(call: MethodCall, callback: OneShotMethodResult) {
        val requestId = requiredString(call, "requestId")
        runAsync(
            callback = callback,
            fallbackCode = LlmRuntimeErrorCode.GENERATION_FAILED,
            stage = LlmRuntimeStage.CANCELLATION,
            requestId = requestId,
            executor = cancellationExecutor,
        ) {
            runtime.cancelGeneration(requestId)
            null
        }
    }

    private fun releaseModel(call: MethodCall, callback: OneShotMethodResult) {
        val modelId = requiredString(call, "modelId")
        runAsync(
            callback = callback,
            fallbackCode = LlmRuntimeErrorCode.RELEASE_FAILED,
            stage = LlmRuntimeStage.RELEASE,
            modelId = modelId,
        ) {
            runtime.releaseModel(modelId)
            null
        }
    }

    private fun requiredString(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("$name is required")
    }

    private fun optionalNonBlankString(call: MethodCall, name: String): String? {
        if (!call.hasArgument(name)) {
            return null
        }
        val value = call.argument<String>(name) ?: return null
        require(value.isNotBlank()) { "$name must not be blank" }
        return value.trim()
    }

    private fun requestId(call: MethodCall): String {
        if (!call.hasArgument("requestId")) {
            return "native-${REQUEST_SEQUENCE.incrementAndGet()}"
        }
        return requiredString(call, "requestId")
    }

    private fun readGenerationConfig(call: MethodCall): LocalLlmGenerationConfig {
        @Suppress("UNCHECKED_CAST")
        val stops = call.argument<List<String>>("stopSequences")
            ?: listOf("</s>", "<|im_end|>", "<|endoftext|>")
        val contextLength = call.argument<Int>("contextLength") ?: HUAWEI_SAFE_CONTEXT_LENGTH
        val maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 96
        val maxPromptChars = call.argument<Int>("maxPromptChars") ?: 1200
        val temperature = call.argument<Number>("temperature")?.toDouble() ?: 0.7
        val topK = call.argument<Int>("topK") ?: 40
        val topP = call.argument<Number>("topP")?.toDouble() ?: 0.9
        require(contextLength > 0) { "contextLength must be positive" }
        require(maxOutputTokens > 0) { "maxOutputTokens must be positive" }
        require(maxPromptChars > 0) { "maxPromptChars must be positive" }
        require(temperature.isFinite() && temperature >= 0.0) { "temperature is invalid" }
        require(topK > 0) { "topK must be positive" }
        require(topP.isFinite() && topP in 0.0..1.0) { "topP is invalid" }
        return LocalLlmGenerationConfig(
            contextLength = contextLength,
            maxOutputTokens = maxOutputTokens,
            maxPromptChars = maxPromptChars,
            conservativeMode = call.argument<Boolean>("conservativeMode") ?: true,
            emitPartialCompletion = call.argument<Boolean>("emitPartialCompletion") ?: false,
            temperature = temperature,
            topK = topK,
            topP = topP,
            seed = call.argument<Int>("seed") ?: 42,
            stopSequences = stops,
        )
    }

    private fun runAsync(
        callback: OneShotMethodResult,
        fallbackCode: LlmRuntimeErrorCode,
        stage: LlmRuntimeStage,
        modelId: String? = null,
        requestId: String? = null,
        executor: Executor = workerExecutor,
        block: () -> Any?,
    ) {
        try {
            executor.execute {
                try {
                    callback.success(block())
                } catch (error: Throwable) {
                    callback.failure(error, fallbackCode, stage, modelId, requestId)
                }
            }
        } catch (error: Throwable) {
            callback.failure(error, fallbackCode, stage, modelId, requestId)
        }
    }

    private fun currentAttachmentEpoch(): Long = synchronized(attachmentLock) {
        attachmentEpoch
    }

    private fun deliverIfCurrent(
        epoch: Long,
        delivered: AtomicBoolean,
        block: () -> Unit,
    ) = synchronized(attachmentLock) {
        if (
            callbacksEnabled &&
            attachmentEpoch == epoch &&
            delivered.compareAndSet(false, true)
        ) {
            block()
        }
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/llm_runtime"
        private val REQUEST_SEQUENCE = AtomicLong(0)
    }
}

private class OneShotMethodResult(
    private val delegate: MethodChannel.Result,
    private val dispatcher: ResultDispatcher,
    private val attachmentEpoch: Long,
    private val deliverIfCurrent: (Long, AtomicBoolean, () -> Unit) -> Unit,
) {
    private val delivered = AtomicBoolean(false)

    fun success(value: Any?) {
        dispatch { delegate.success(value) }
    }

    fun error(code: String, message: String?, details: Any?) {
        dispatch { delegate.error(code, message, details) }
    }

    fun notImplemented() {
        dispatch(delegate::notImplemented)
    }

    fun failure(
        error: Throwable,
        fallbackCode: LlmRuntimeErrorCode,
        stage: LlmRuntimeStage,
        modelId: String? = null,
        requestId: String? = null,
    ) {
        val typed = when (error) {
            is LlmRuntimeException -> error.withModelId(modelId).withRequestId(requestId)
            is IllegalArgumentException -> LlmRuntimeException(
                code = LlmRuntimeErrorCode.INVALID_ARGUMENT,
                stage = LlmRuntimeStage.ARGUMENT,
                modelId = modelId,
                requestId = requestId,
            )
            else -> LlmRuntimeException(
                code = fallbackCode,
                stage = stage,
                modelId = modelId,
                requestId = requestId,
            )
        }
        val details = buildMap<String, String> {
            put("stage", typed.stage.wireName)
            typed.modelId?.let { put("modelId", it) }
            typed.requestId?.let { put("requestId", it) }
        }
        error(
            code = typed.code.wireName,
            message = typed.code.wireName,
            details = details,
        )
    }

    private fun dispatch(block: () -> Unit) {
        dispatcher.dispatch {
            deliverIfCurrent(attachmentEpoch, delivered, block)
        }
    }
}

interface ResultDispatcher {
    fun dispatch(block: () -> Unit)
}

class MainThreadResultDispatcher(
    private val handler: Handler = Handler(Looper.getMainLooper()),
) : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        handler.post(block)
    }
}
