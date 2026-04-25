package com.example.note_secret_search

import android.content.Context
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.FloatBuffer

class OnnxEmbeddingRuntime(
    private val context: Context,
    private val sessionManager: EmbeddingModelSessionManager,
) {
    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment()

    fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
        val file = File(modelPath)
        if (!file.exists()) {
            return runtimeState(
                status = "missing",
                reason = "当前本地 embedding 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
            )
        }

        return try {
            val session = createSession(file)
            val vectorDimension = inferVectorDimension(session)
            session.close()
            runtimeState(
                status = "ready",
                reason = "本地 embedding runtime 已就绪。",
                modelPath = modelPath,
                vectorDimension = vectorDimension,
            )
        } catch (error: Throwable) {
            runtimeState(
                status = "degraded",
                reason = "模型已安装但当前不可运行：${error.message ?: "unknown error"}",
                modelPath = modelPath,
            )
        }
    }

    fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
        val file = File(modelPath)
        if (!file.exists()) {
            return runtimeState(
                status = "missing",
                reason = "当前本地 embedding 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
            )
        }

        return try {
            val existing = sessionManager.get(modelId)
            val session = existing ?: createSession(file).also { sessionManager.replace(modelId, it) }
            val vectorDimension = inferVectorDimension(session)
            runtimeState(
                status = "ready",
                reason = "本地 embedding runtime 已就绪。",
                modelPath = modelPath,
                vectorDimension = vectorDimension,
            )
        } catch (error: Throwable) {
            sessionManager.release(modelId)
            runtimeState(
                status = "degraded",
                reason = "模型已安装但当前不可运行：${error.message ?: "unknown error"}",
                modelPath = modelPath,
            )
        }
    }

    fun embedText(modelId: String, modelPath: String, text: String): Map<String, Any?> {
        require(text.isNotBlank()) { "Text for embedding must not be blank." }

        val ready = ensureModelReady(modelId, modelPath)
        if (ready["status"] != "ready") {
            throw IllegalStateException(ready["reason"] as? String ?: "Embedding runtime is not ready.")
        }

        val session = sessionManager.get(modelId)
            ?: throw IllegalStateException("Embedding session was not prepared.")

        val outputVector = runMinimalInference(session, text)
        return mapOf(
            "values" to outputVector,
            "tokenCount" to text.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.size,
            "vectorDimension" to outputVector.size,
        )
    }

    fun releaseModel(modelId: String) {
        sessionManager.release(modelId)
    }

    private fun createSession(file: File): OrtSession {
        val sessionOptions = OrtSession.SessionOptions()
        return try {
            environment.createSession(file.absolutePath, sessionOptions)
        } finally {
            sessionOptions.close()
        }
    }

    private fun inferVectorDimension(session: OrtSession): Int? {
        val outputInfo = session.outputInfo.values.firstOrNull() ?: return null
        val shape = outputInfo.info.shape
        val positiveDims = shape.filter { it > 0 }
        return positiveDims.lastOrNull()?.toInt()
    }

    private fun runMinimalInference(session: OrtSession, text: String): List<Double> {
        val tensorInputName = session.inputNames.firstOrNull()
            ?: throw OrtException("MODEL_SCHEMA_UNSUPPORTED: no ONNX input found")

        val values = textToFloatInput(text)
        val shape = longArrayOf(1, values.size.toLong())
        val tensor = OnnxTensor.createTensor(environment, FloatBuffer.wrap(values), shape)

        tensor.use { inputTensor ->
            session.run(mapOf(tensorInputName to inputTensor)).use { outputs ->
                val first = outputs.firstOrNull()?.value
                    ?: throw OrtException("EMPTY_OUTPUT: no embedding output returned")

                val floats = extractFloatValues(first)
                if (floats.isEmpty()) {
                    throw OrtException("EMPTY_OUTPUT: embedding vector is empty")
                }
                return normalize(floats)
            }
        }
    }

    private fun textToFloatInput(text: String): FloatArray {
        val normalized = text.trim()
        if (normalized.isEmpty()) {
            return floatArrayOf(0f)
        }

        val maxLength = 64
        val chars = normalized.take(maxLength)
        return FloatArray(chars.length) { index ->
            chars[index].code.toFloat()
        }
    }

    private fun extractFloatValues(value: Any): List<Double> {
        return when (value) {
            is FloatArray -> value.map(Float::toDouble)
            is Array<*> -> flattenArray(value)
            else -> emptyList()
        }
    }

    private fun flattenArray(value: Array<*>): List<Double> {
        val flattened = mutableListOf<Double>()
        value.forEach { item ->
            when (item) {
                is FloatArray -> flattened.addAll(item.map(Float::toDouble))
                is Array<*> -> flattened.addAll(flattenArray(item))
            }
        }
        return flattened
    }

    private fun normalize(values: List<Double>): List<Double> {
        val norm = kotlin.math.sqrt(values.sumOf { it * it })
        if (norm == 0.0) {
            return values
        }
        return values.map { it / norm }
    }

    private fun runtimeState(
        status: String,
        reason: String,
        modelPath: String,
        vectorDimension: Int? = null,
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "reason" to reason,
            "vectorDimension" to vectorDimension,
            "checkedAt" to System.currentTimeMillis(),
            "modelPath" to modelPath,
            "runtime" to "onnx",
            "supportsEmbedding" to (status == "ready"),
            "contextPackage" to context.packageName,
        )
    }
}
