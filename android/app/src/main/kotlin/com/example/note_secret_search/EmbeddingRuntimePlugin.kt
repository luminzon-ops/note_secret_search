package com.example.note_secret_search

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EmbeddingRuntimePlugin(
    context: Context,
) : MethodChannel.MethodCallHandler {

    private val runtime = OnnxEmbeddingRuntime(
        context = context,
        sessionManager = EmbeddingModelSessionManager(),
    )

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
                    result.success(runtime.inspectModel(modelId = modelId, modelPath = modelPath))
                }

                "ensureModelReady" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    result.success(runtime.ensureModelReady(modelId = modelId, modelPath = modelPath))
                }

                "embedText" -> {
                    val modelId = requiredString(call, "modelId")
                    val modelPath = requiredString(call, "modelPath")
                    val text = requiredString(call, "text")
                    result.success(runtime.embedText(modelId = modelId, modelPath = modelPath, text = text))
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
            result.error("EMBEDDING_RUNTIME_ERROR", error.message, null)
        }
    }

    private fun requiredString(call: MethodCall, name: String): String {
        return call.argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("$name is required")
    }

    companion object {
        private const val CHANNEL_NAME = "note_secret_search/embedding_runtime"
    }
}
