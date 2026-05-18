package com.example.note_secret_search

import android.content.Context
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer
import org.json.JSONObject

class OnnxEmbeddingRuntime(
    private val context: Context,
    private val sessionManager: EmbeddingModelSessionManager,
) {
    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment()

    fun inspectModel(modelId: String, modelPath: String, spec: OnnxEmbeddingModelSpec): Map<String, Any?> {
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
            validateSpec(session, spec)
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

    fun ensureModelReady(modelId: String, modelPath: String, spec: OnnxEmbeddingModelSpec): Map<String, Any?> {
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
            validateSpec(session, spec)
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

    fun embedText(modelId: String, modelPath: String, text: String, spec: OnnxEmbeddingModelSpec): Map<String, Any?> {
        require(text.isNotBlank()) { "Text for embedding must not be blank." }

        val ready = ensureModelReady(modelId, modelPath, spec)
        if (ready["status"] != "ready") {
            throw IllegalStateException(ready["reason"] as? String ?: "Embedding runtime is not ready.")
        }

        val session = sessionManager.get(modelId)
            ?: throw IllegalStateException("Embedding session was not prepared.")

        val encoded = loadTokenizer(spec.tokenizer).encode(text)
        val outputVector = runMinimalInference(session, encoded, spec)
        return mapOf(
            "values" to outputVector,
            "tokenCount" to encoded.attentionMask.count { it == 1L },
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
        val tensorInfo = outputInfo.info as? TensorInfo ?: return null
        val positiveDims = tensorInfo.shape.filter { it > 0L }
        return positiveDims.lastOrNull()?.toInt()
    }

    private fun runMinimalInference(
        session: OrtSession,
        encoded: EncodedEmbeddingInput,
        spec: OnnxEmbeddingModelSpec,
    ): List<Double> {
        val sequenceLength = encoded.inputIds.size.toLong()
        val shape = longArrayOf(1, sequenceLength)

        val inputIdsTensor = OnnxTensor.createTensor(
            environment,
            LongBuffer.wrap(encoded.inputIds),
            shape,
        )
        val attentionMaskTensor = OnnxTensor.createTensor(
            environment,
            LongBuffer.wrap(encoded.attentionMask),
            shape,
        )
        val tokenTypeIdsTensor = spec.runtime.tokenTypeIdsName?.let {
            OnnxTensor.createTensor(environment, LongBuffer.wrap(encoded.tokenTypeIds), shape)
        }

        inputIdsTensor.use { ids ->
            attentionMaskTensor.use { mask ->
                tokenTypeIdsTensor.use { tokenTypes ->
                    val inputs = mutableMapOf<String, OnnxTensor>(
                        spec.runtime.inputIdsName to ids,
                        spec.runtime.attentionMaskName to mask,
                    )
                    if (spec.runtime.tokenTypeIdsName != null && tokenTypes != null) {
                        inputs[spec.runtime.tokenTypeIdsName] = tokenTypes
                    }

                    session.run(inputs).use { outputs ->
                        val selected = outputs.firstOrNull { it.key == spec.runtime.outputName }?.value
                            ?: outputs.firstOrNull()?.value
                            ?: throw OrtException("EMPTY_OUTPUT: no embedding output returned")

                        val tokenVectors = extractTokenVectors(selected)
                        val floats = when {
                            tokenVectors != null -> EmbeddingVectorPostProcessor.pool(
                                tokenVectors = tokenVectors,
                                attentionMask = encoded.attentionMask,
                                pooling = spec.runtime.pooling,
                            )

                            else -> extractFloatValues(selected)
                        }
                        if (floats.isEmpty()) {
                            throw OrtException("EMPTY_OUTPUT: embedding vector is empty")
                        }
                        return EmbeddingVectorPostProcessor.normalize(
                            values = floats,
                            normalization = spec.runtime.normalization,
                        )
                    }
                }
            }
        }
    }

    private fun loadTokenizer(spec: OnnxEmbeddingModelSpec.TokenizerSpec): WordpieceEmbeddingTokenizer {
        val raw = context.assets.open("flutter_assets/${spec.assetPath}").bufferedReader().use { it.readText() }
        val vocab = extractVocabulary(raw)
        return WordpieceEmbeddingTokenizer(
            vocab = vocab,
            lowercase = spec.lowercase,
            maxSequenceLength = spec.maxSequenceLength,
        )
    }

    private fun extractFloatValues(value: Any): List<Double> {
        return when (value) {
            is FloatArray -> value.map(Float::toDouble)
            is Array<*> -> flattenArray(value)
            else -> emptyList()
        }
    }

    private fun extractTokenVectors(value: Any): Array<FloatArray>? {
        return when (value) {
            is Array<*> -> {
                val first = value.firstOrNull()
                when (first) {
                    is FloatArray -> arrayOf(first)
                    is Array<*> -> first.mapNotNull { it as? FloatArray }.toTypedArray().takeIf { it.isNotEmpty() }
                    else -> null
                }
            }

            else -> null
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

    private fun validateSpec(session: OrtSession, spec: OnnxEmbeddingModelSpec) {
        context.assets.open("flutter_assets/${spec.tokenizer.assetPath}").close()

        val inputNames = session.inputNames
        require(inputNames.contains(spec.runtime.inputIdsName)) {
            "MODEL_SCHEMA_UNSUPPORTED: missing input ${spec.runtime.inputIdsName}"
        }
        require(inputNames.contains(spec.runtime.attentionMaskName)) {
            "MODEL_SCHEMA_UNSUPPORTED: missing input ${spec.runtime.attentionMaskName}"
        }
        if (spec.runtime.tokenTypeIdsName != null) {
            require(inputNames.contains(spec.runtime.tokenTypeIdsName)) {
                "MODEL_SCHEMA_UNSUPPORTED: missing input ${spec.runtime.tokenTypeIdsName}"
            }
        }

        require(session.outputInfo.containsKey(spec.runtime.outputName)) {
            "MODEL_SCHEMA_UNSUPPORTED: missing output ${spec.runtime.outputName}"
        }
    }

    private fun extractVocabulary(rawJson: String): Map<String, Int> {
        val root = JSONObject(rawJson)
        val model = root.optJSONObject("model")
        val vocabObject = model?.optJSONObject("vocab")
            ?: root.optJSONObject("vocab")
            ?: throw IllegalArgumentException("TOKENIZER_SCHEMA_UNSUPPORTED: vocab not found")

        val vocab = mutableMapOf<String, Int>()
        val keys = vocabObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            vocab[key] = vocabObject.getInt(key)
        }
        return vocab
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
