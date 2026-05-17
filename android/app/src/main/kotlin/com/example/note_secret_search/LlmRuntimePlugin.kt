package com.example.note_secret_search

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.Executors

class LlmRuntimePlugin(
    context: Context? = null,
    private val runtime: LocalLlmRuntimeContract = LocalLlmRuntime(
        context = requireNotNull(context) { "context is required when runtime is not provided" },
        sessionManager = LlmModelSessionManager(),
    ),
    private val multimodalRuntime: MultimodalLlmRuntimeContract = FallbackMultimodalLlmRuntime(),
    private val workerExecutor: Executor = Executors.newSingleThreadExecutor(),
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
) : MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel

    fun attachToEngine(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "inspectModel" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    logInfo("inspectModel call modelId=$modelId path=$modelPath")
                    runAsync(result) {
                        val payload = runtime.inspectModel(modelId = modelId, modelPath = modelPath)
                        logInfo("inspectModel result modelId=$modelId status=${payload["status"]} ready=${payload["ready"]}")
                        payload
                    }
                }

                "ensureModelReady" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    logInfo("ensureModelReady call modelId=$modelId path=$modelPath")
                    runAsync(result) {
                        val payload = runtime.ensureModelReady(modelId = modelId, modelPath = modelPath)
                        logInfo("ensureModelReady result modelId=$modelId status=${payload["status"]} ready=${payload["ready"]}")
                        payload
                    }
                }

                "generateText" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val prompt = requiredString(call, "prompt")
                    val usedPrivateContext = call.argument<Boolean>("usedPrivateContext") ?: false
                    val config = readGenerationConfig(call)
                    logInfo(
                        "generateText call modelId=$modelId path=$modelPath " +
                            "usedPrivateContext=$usedPrivateContext maxOutputTokens=${config.maxOutputTokens} " +
                            "maxPromptChars=${config.maxPromptChars} contextLength=${config.contextLength} " +
                            "conservativeMode=${config.conservativeMode}",
                    )
                    runAsync(result) {
                        runtime.generateText(
                            modelId = modelId,
                            modelPath = modelPath,
                            prompt = prompt,
                            usedPrivateContext = usedPrivateContext,
                            config = config,
                        )
                    }
                }

                "ensureMultimodalModelReady" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val mmprojPath = requiredString(call, "mmprojPath")
                    logInfo("ensureMultimodalModelReady call modelId=$modelId path=$modelPath mmproj=$mmprojPath")
                    runAsync(result) {
                        multimodalRuntime.ensureModelReady(
                            modelId = modelId,
                            modelPath = modelPath,
                            mmprojPath = mmprojPath,
                        )
                    }
                }

                "generateMultimodalText" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val mmprojPath = requiredString(call, "mmprojPath")
                    val imagePath = requiredString(call, "imagePath")
                    val prompt = requiredString(call, "prompt")
                    val config = readGenerationConfig(call)
                    val reasoningEnabled = call.argument<Boolean>("reasoningEnabled") ?: false
                    logInfo(
                        "generateMultimodalText call modelId=$modelId path=$modelPath " +
                            "mmproj=$mmprojPath image=$imagePath reasoningEnabled=$reasoningEnabled",
                    )
                    runAsync(result) {
                        multimodalRuntime.generateMultimodalText(
                            modelId = modelId,
                            modelPath = modelPath,
                            mmprojPath = mmprojPath,
                            imagePath = imagePath,
                            prompt = prompt,
                            config = config,
                            reasoningEnabled = reasoningEnabled,
                        )
                    }
                }

                "releaseModel" -> {
                    val modelId = requiredString(call, "modelId")
                    runtime.releaseModel(modelId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (error: IllegalArgumentException) {
            result.error("INVALID_ARGUMENT", error.message, null)
        } catch (error: IllegalStateException) {
            result.error("RUNTIME_NOT_READY", error.message, null)
        } catch (error: Throwable) {
            result.error("LLM_RUNTIME_ERROR", error.message, null)
        }
    }

    private fun requiredString(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("$name is required")
    }

    private fun readGenerationConfig(call: MethodCall): LocalLlmGenerationConfig {
        @Suppress("UNCHECKED_CAST")
        val stops = call.argument<List<String>>("stopSequences")
            ?: listOf("</s>", "<|im_end|>", "<|endoftext|>")
        return LocalLlmGenerationConfig(
            contextLength = call.argument<Int>("contextLength") ?: HUAWEI_SAFE_CONTEXT_LENGTH,
            maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 96,
            maxPromptChars = call.argument<Int>("maxPromptChars") ?: 1200,
            conservativeMode = call.argument<Boolean>("conservativeMode") ?: true,
            emitPartialCompletion = false,
            temperature = (call.argument<Number>("temperature")?.toDouble()) ?: 0.7,
            topK = call.argument<Int>("topK") ?: 40,
            topP = (call.argument<Number>("topP")?.toDouble()) ?: 0.9,
            seed = call.argument<Int>("seed") ?: 42,
            stopSequences = stops,
        )
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        workerExecutor.execute {
            try {
                val payload = block()
                resultDispatcher.dispatch { result.success(payload) }
            } catch (error: IllegalArgumentException) {
                resultDispatcher.dispatch { result.error("INVALID_ARGUMENT", error.message, null) }
            } catch (error: IllegalStateException) {
                resultDispatcher.dispatch { result.error("RUNTIME_NOT_READY", error.message, null) }
            } catch (error: Throwable) {
                resultDispatcher.dispatch { result.error("LLM_RUNTIME_ERROR", error.message, null) }
            }
        }
    }

    private fun logInfo(message: String) {
        runLoggingSafely { Log.i(TAG, message) }
    }

    private inline fun runLoggingSafely(block: () -> Unit) {
        try {
            block()
        } catch (_: RuntimeException) {
        }
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/llm_runtime"
        private const val TAG = "LlmRuntimePlugin"
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
