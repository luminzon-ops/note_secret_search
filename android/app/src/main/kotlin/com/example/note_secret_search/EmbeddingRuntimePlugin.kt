package com.example.note_secret_search

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class EmbeddingRuntimePlugin(
    context: Context? = null,
    private val runtime: EmbeddingRuntimeContract = OnnxEmbeddingRuntime(
        context = requireNotNull(context) {
            "context is required when runtime is not provided"
        },
        sessionManager = EmbeddingModelSessionManager(),
    ),
    private val worker: EmbeddingRuntimeWorker = EmbeddingRuntimeWorker(),
    private val resultDispatcher: ResultDispatcher = MainThreadResultDispatcher(),
) : MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    fun attachToEngine(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val completion = EmbeddingMethodCompletion(result, resultDispatcher)
        try {
            when (call.method) {
                "inspectModel" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val spec = readSpec(call)
                    runAsync(modelId, completion) {
                        runtime.inspectModel(
                            modelId = modelId,
                            modelPath = modelPath,
                            spec = spec,
                        )
                    }
                }

                "ensureModelReady" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val spec = readSpec(call)
                    runAsync(modelId, completion) {
                        runtime.ensureModelReady(
                            modelId = modelId,
                            modelPath = modelPath,
                            spec = spec,
                        )
                    }
                }

                "embedText" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val text = requiredString(call, "text")
                    val spec = readSpec(call)
                    runAsync(modelId, completion) {
                        runtime.embedText(
                            modelId = modelId,
                            modelPath = modelPath,
                            text = text,
                            spec = spec,
                        )
                    }
                }

                "releaseModel" -> {
                    val modelId = requiredString(call, "modelId")
                    runAsync(modelId, completion) {
                        runtime.releaseModel(modelId)
                        null
                    }
                }

                else -> completion.notImplemented()
            }
        } catch (error: Throwable) {
            completion.error(
                normalizePluginFailure(
                    error = error,
                    modelId = call.argument<String>("modelId"),
                ),
            )
        }
    }

    private fun runAsync(
        modelId: String,
        completion: EmbeddingMethodCompletion,
        block: () -> Any?,
    ) {
        val item = EmbeddingWorkItem(
            modelId = modelId,
            execute = {
                try {
                    completion.success(block())
                } catch (error: Throwable) {
                    completion.error(
                        normalizePluginFailure(
                            error = error,
                            modelId = modelId,
                        ),
                    )
                }
            },
            onDropped = completion::error,
        )
        when (worker.submit(item)) {
            EmbeddingWorkSubmission.ACCEPTED -> Unit
            EmbeddingWorkSubmission.BUSY -> completion.error(
                EmbeddingRuntimeException(
                    code = EmbeddingRuntimeErrorCode.BUSY,
                    stage = EmbeddingRuntimeStage.QUEUE,
                    modelId = modelId,
                ),
            )
            EmbeddingWorkSubmission.CLOSED -> completion.error(
                EmbeddingRuntimeException(
                    code = EmbeddingRuntimeErrorCode.RUNTIME_CLOSED,
                    stage = EmbeddingRuntimeStage.LIFECYCLE,
                    modelId = modelId,
                ),
            )
        }
    }

    private fun normalizePluginFailure(
        error: Throwable,
        modelId: String?,
    ): EmbeddingRuntimeException {
        if (error is EmbeddingRuntimeException) {
            return error.withModelId(modelId)
        }
        val code = if (error is IllegalArgumentException) {
            EmbeddingRuntimeErrorCode.INVALID_ARGUMENT
        } else {
            EmbeddingRuntimeErrorCode.ORT_FAILURE
        }
        val stage = if (code == EmbeddingRuntimeErrorCode.INVALID_ARGUMENT) {
            EmbeddingRuntimeStage.ARGUMENT
        } else {
            EmbeddingRuntimeStage.INFERENCE
        }
        return EmbeddingRuntimeException.wrap(
            error = error,
            code = code,
            stage = stage,
            modelId = modelId,
        )
    }

    private fun requiredString(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.INVALID_ARGUMENT,
                stage = EmbeddingRuntimeStage.ARGUMENT,
                modelId = call.argument<String>("modelId"),
            )
    }

    @Suppress("UNCHECKED_CAST")
    private fun readSpec(call: MethodCall): OnnxEmbeddingModelSpec {
        val tokenizer = call.argument<Map<String, Any?>>("tokenizer")
        val runtime = call.argument<Map<String, Any?>>("runtime")
        return OnnxEmbeddingModelSpec.fromMaps(
            tokenizer = tokenizer as Map<*, *>?,
            runtime = runtime as Map<*, *>?,
        ) ?: throw EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.INVALID_ARGUMENT,
            stage = EmbeddingRuntimeStage.ARGUMENT,
            modelId = call.argument<String>("modelId"),
        )
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/embedding_runtime"
    }
}

private class EmbeddingMethodCompletion(
    private val result: MethodChannel.Result,
    private val dispatcher: ResultDispatcher,
) {
    private val completed = AtomicBoolean(false)

    fun success(payload: Any?) {
        dispatch { result.success(payload) }
    }

    fun error(error: EmbeddingRuntimeException) {
        dispatch {
            result.error(
                error.code.wireName,
                error.code.wireName,
                buildMap {
                    put("stage", error.stage.wireName)
                    error.modelId?.let { put("modelId", it) }
                },
            )
        }
    }

    fun notImplemented() {
        dispatch(result::notImplemented)
    }

    private fun dispatch(block: () -> Unit) {
        dispatcher.dispatch {
            if (completed.compareAndSet(false, true)) {
                block()
            }
        }
    }
}
