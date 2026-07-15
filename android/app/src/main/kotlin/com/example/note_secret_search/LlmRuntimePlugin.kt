package com.example.note_secret_search

import android.content.Context
import android.os.Handler
import android.os.Looper
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
                    runAsync(result) {
                        runtime.inspectModel(
                            modelId = modelId,
                            modelPath = modelPath,
                        )
                    }
                }

                "ensureModelReady" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    runAsync(result) {
                        runtime.ensureModelReady(
                            modelId = modelId,
                            modelPath = modelPath,
                        )
                    }
                }

                "generateText" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val prompt = requiredString(call, "prompt")
                    val usedPrivateContext = call.argument<Boolean>("usedPrivateContext") ?: false
                    val config = readGenerationConfig(call)
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
                    result.error(
                        "UNSUPPORTED_CAPABILITY",
                        "UNSUPPORTED_CAPABILITY",
                        null,
                    )
                }

                "generateMultimodalText" -> {
                    result.error(
                        "UNSUPPORTED_CAPABILITY",
                        "UNSUPPORTED_CAPABILITY",
                        null,
                    )
                }

                "releaseModel" -> {
                    val modelId = requiredString(call, "modelId")
                    runtime.releaseModel(modelId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (_: IllegalArgumentException) {
            result.error(
                "INVALID_ARGUMENT",
                "Invalid LLM runtime request.",
                null,
            )
        } catch (_: IllegalStateException) {
            result.error(
                "RUNTIME_NOT_READY",
                "Local LLM runtime is not ready.",
                null,
            )
        } catch (_: Throwable) {
            result.error(
                "LLM_RUNTIME_ERROR",
                "Local LLM runtime failed.",
                null,
            )
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
            emitPartialCompletion = call.argument<Boolean>("emitPartialCompletion") ?: false,
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
            } catch (_: IllegalArgumentException) {
                resultDispatcher.dispatch {
                    result.error(
                        "INVALID_ARGUMENT",
                        "Invalid LLM runtime request.",
                        null,
                    )
                }
            } catch (_: IllegalStateException) {
                resultDispatcher.dispatch {
                    result.error(
                        "RUNTIME_NOT_READY",
                        "Local LLM runtime is not ready.",
                        null,
                    )
                }
            } catch (_: Throwable) {
                resultDispatcher.dispatch {
                    result.error(
                        "LLM_RUNTIME_ERROR",
                        "Local LLM runtime failed.",
                        null,
                    )
                }
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/llm_runtime"
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
