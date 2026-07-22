package com.example.note_secret_search

import android.content.Context
import java.io.File

fun interface EmbeddingTokenizerLoader {
    fun load(spec: OnnxEmbeddingModelSpec.TokenizerSpec): WordpieceEmbeddingTokenizer
}

class OnnxEmbeddingRuntime(
    private val tokenizerLoader: EmbeddingTokenizerLoader,
    private val sessionManager: EmbeddingModelSessionManager,
    private val adapter: OnnxRuntimeAdapter,
    private val contextPackage: String,
    private val executionSettings: OrtExecutionSettings = OrtExecutionSettings.controlled(),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    constructor(
        context: Context,
        sessionManager: EmbeddingModelSessionManager,
    ) : this(
        tokenizerLoader = EmbeddingTokenizerLoader { spec ->
            val raw = context.assets
                .open("flutter_assets/${spec.assetPath}")
                .bufferedReader()
                .use { it.readText() }
            WordpieceEmbeddingTokenizer(
                definition = TokenizerJsonParser.parse(
                    rawJson = raw,
                    expectedLowercase = spec.lowercase,
                ),
                maxSequenceLength = spec.maxSequenceLength,
            )
        },
        sessionManager = sessionManager,
        adapter = OrtOnnxRuntimeAdapter(),
        contextPackage = context.packageName,
    )

    fun inspectModel(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?> {
        val file = File(modelPath)
        if (!file.exists()) {
            return runtimeState(
                status = "missing",
                reason = "当前本地 embedding 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
            )
        }

        return try {
            tokenizerLoader.load(spec.tokenizer)
            val prepared = openPreparedSession(file, spec)
            prepared.use {
                runtimeState(
                    status = "ready",
                    reason = "本地 embedding runtime 已就绪。",
                    modelPath = modelPath,
                    vectorDimension = prepared.contract.vectorDimension,
                )
            }
        } catch (error: Throwable) {
            runtimeState(
                status = "degraded",
                reason = "模型已安装但当前不可运行：${error.message ?: "unknown error"}",
                modelPath = modelPath,
            )
        }
    }

    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?> {
        val file = File(modelPath)
        if (!file.exists()) {
            return runtimeState(
                status = "missing",
                reason = "当前本地 embedding 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
            )
        }

        return try {
            tokenizerLoader.load(spec.tokenizer)
            val prepared = sessionManager.get(modelId)
                ?: openPreparedSession(file, spec).also {
                    sessionManager.replace(modelId, it)
                }
            runtimeState(
                status = "ready",
                reason = "本地 embedding runtime 已就绪。",
                modelPath = modelPath,
                vectorDimension = prepared.contract.vectorDimension,
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

    fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?> {
        require(text.isNotBlank()) { "Text for embedding must not be blank." }

        val ready = ensureModelReady(modelId, modelPath, spec)
        if (ready["status"] != "ready") {
            throw IllegalStateException(
                ready["reason"] as? String ?: "Embedding runtime is not ready.",
            )
        }

        val prepared = sessionManager.get(modelId)
            ?: throw IllegalStateException("Embedding session was not prepared.")
        val tokenizer = tokenizerLoader.load(spec.tokenizer)
        val encoded = tokenizer.encode(
            text = text,
            padToLength = prepared.contract.fixedSequenceLength,
        )
        val outputVector = runInference(prepared, encoded, spec.runtime)
        return mapOf(
            "values" to outputVector,
            "tokenCount" to encoded.attentionMask.count { it == 1L },
            "vectorDimension" to outputVector.size,
        )
    }

    fun releaseModel(modelId: String) {
        sessionManager.release(modelId)
    }

    private fun openPreparedSession(
        file: File,
        spec: OnnxEmbeddingModelSpec,
    ): PreparedEmbeddingSession {
        val handle = adapter.openSession(
            modelPath = file.absolutePath,
            settings = executionSettings,
        )
        return try {
            PreparedEmbeddingSession(
                handle = handle,
                contract = ModelIoContractBuilder.build(
                    graph = handle.graph,
                    runtime = spec.runtime,
                ),
            )
        } catch (error: Throwable) {
            handle.close()
            throw error
        }
    }

    private fun runInference(
        prepared: PreparedEmbeddingSession,
        encoded: EncodedEmbeddingInput,
        runtime: OnnxEmbeddingModelSpec.RuntimeSpec,
    ): List<Double> {
        val contract = prepared.contract
        val shape = longArrayOf(1, encoded.inputIds.size.toLong())
        val inputs = linkedMapOf(
            contract.inputIds.name to IntegralTensorData(
                type = contract.inputIds.type,
                shape = shape,
                values = encoded.inputIds,
            ),
            contract.attentionMask.name to IntegralTensorData(
                type = contract.attentionMask.type,
                shape = shape,
                values = encoded.attentionMask,
            ),
        )
        contract.tokenTypeIds?.let { input ->
            inputs[input.name] = IntegralTensorData(
                type = input.type,
                shape = shape,
                values = encoded.tokenTypeIds,
            )
        }

        val decoded = EmbeddingTensorDecoder.decode(
            prepared.handle.run(
                inputs = inputs,
                outputName = contract.outputName,
            ),
        )
        val pooled = when (decoded.kind) {
            EmbeddingTensorKind.TOKEN -> EmbeddingVectorPostProcessor.pool(
                tokenVectors = decoded.tokenVectors,
                attentionMask = encoded.attentionMask,
                pooling = runtime.pooling,
            )

            EmbeddingTensorKind.SENTENCE -> {
                require(runtime.pooling == "none") {
                    "INVALID_OUTPUT: sentence output requires pooling=none"
                }
                decoded.sentenceVector.map(Float::toDouble)
            }
        }
        return EmbeddingVectorPostProcessor.normalize(
            values = pooled,
            normalization = runtime.normalization,
        )
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
            "checkedAt" to clock(),
            "modelPath" to modelPath,
            "runtime" to "onnx",
            "supportsEmbedding" to (status == "ready"),
            "contextPackage" to contextPackage,
        )
    }
}
