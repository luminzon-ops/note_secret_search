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
) : EmbeddingRuntimeContract {
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

    override fun inspectModel(
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
            loadTokenizer(modelId, spec.tokenizer)
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
            val typed = normalizeFailure(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.SESSION_LOAD,
                modelId = modelId,
            )
            runtimeState(
                status = "degraded",
                reason = typed.code.wireName,
                modelPath = modelPath,
                error = typed,
            )
        }
    }

    override fun ensureModelReady(
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
            loadTokenizer(modelId, spec.tokenizer)
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
            val typed = normalizeFailure(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.SESSION_LOAD,
                modelId = modelId,
            )
            runtimeState(
                status = "degraded",
                reason = typed.code.wireName,
                modelPath = modelPath,
                error = typed,
            )
        }
    }

    override fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?> {
        if (text.isBlank()) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.INVALID_ARGUMENT,
                stage = EmbeddingRuntimeStage.ARGUMENT,
                modelId = modelId,
            )
        }

        val file = File(modelPath)
        if (!file.exists()) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.MODEL_MISSING,
                stage = EmbeddingRuntimeStage.MODEL_LOOKUP,
                modelId = modelId,
            )
        }

        return try {
            val tokenizer = loadTokenizer(modelId, spec.tokenizer)
            val prepared = sessionManager.get(modelId)
                ?: openPreparedSession(file, spec).also {
                    sessionManager.replace(modelId, it)
                }
            val encoded = tokenizer.encode(
                text = text,
                padToLength = prepared.contract.fixedSequenceLength,
            )
            val outputVector = runInference(
                prepared = prepared,
                encoded = encoded,
                runtime = spec.runtime,
                modelId = modelId,
            )
            mapOf(
                "values" to outputVector,
                "tokenCount" to encoded.attentionMask.count { it == 1L },
                "vectorDimension" to outputVector.size,
            )
        } catch (error: Throwable) {
            throw normalizeFailure(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.INFERENCE,
                modelId = modelId,
            )
        }
    }

    override fun releaseModel(modelId: String) {
        sessionManager.release(modelId)
    }

    override fun releaseAll() {
        sessionManager.releaseAll()
    }

    private fun openPreparedSession(
        file: File,
        spec: OnnxEmbeddingModelSpec,
    ): PreparedEmbeddingSession {
        val handle = try {
            adapter.openSession(
                modelPath = file.absolutePath,
                settings = executionSettings,
            )
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.SESSION_LOAD,
            )
        }
        return try {
            PreparedEmbeddingSession(
                handle = handle,
                contract = ModelIoContractBuilder.build(
                    graph = handle.graph,
                    runtime = spec.runtime,
                ),
            )
        } catch (error: Throwable) {
            try {
                handle.close()
            } catch (closeError: Throwable) {
                error.addSuppressed(closeError)
            }
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.MODEL_SCHEMA_UNSUPPORTED,
                stage = EmbeddingRuntimeStage.MODEL_SCHEMA,
            )
        }
    }

    private fun runInference(
        prepared: PreparedEmbeddingSession,
        encoded: EncodedEmbeddingInput,
        runtime: OnnxEmbeddingModelSpec.RuntimeSpec,
        modelId: String,
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

        val output = try {
            prepared.handle.run(
                inputs = inputs,
                outputName = contract.outputName,
            )
        } catch (error: Throwable) {
            throw classifyInferenceFailure(error, modelId)
        }
        return try {
            val decoded = EmbeddingTensorDecoder.decode(output)
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
            EmbeddingVectorPostProcessor.normalize(
                values = pooled,
                normalization = runtime.normalization,
            )
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.INVALID_OUTPUT,
                stage = EmbeddingRuntimeStage.OUTPUT,
                modelId = modelId,
            )
        }
    }

    private fun loadTokenizer(
        modelId: String,
        spec: OnnxEmbeddingModelSpec.TokenizerSpec,
    ): WordpieceEmbeddingTokenizer {
        return try {
            tokenizerLoader.load(spec)
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.TOKENIZER_SCHEMA_UNSUPPORTED,
                stage = EmbeddingRuntimeStage.TOKENIZER,
                modelId = modelId,
            )
        }
    }

    private fun classifyInferenceFailure(
        error: Throwable,
        modelId: String,
    ): EmbeddingRuntimeException {
        if (error is EmbeddingRuntimeException) {
            return error.withModelId(modelId)
        }
        val message = error.message.orEmpty()
        val code = when {
            message.startsWith("INVALID_OUTPUT:") -> EmbeddingRuntimeErrorCode.INVALID_OUTPUT
            message.startsWith("MODEL_SCHEMA_UNSUPPORTED:") ->
                EmbeddingRuntimeErrorCode.MODEL_SCHEMA_UNSUPPORTED
            else -> EmbeddingRuntimeErrorCode.ORT_FAILURE
        }
        val stage = when (code) {
            EmbeddingRuntimeErrorCode.INVALID_OUTPUT -> EmbeddingRuntimeStage.OUTPUT
            EmbeddingRuntimeErrorCode.MODEL_SCHEMA_UNSUPPORTED ->
                EmbeddingRuntimeStage.MODEL_SCHEMA
            else -> EmbeddingRuntimeStage.INFERENCE
        }
        return EmbeddingRuntimeException.wrap(
            error = error,
            code = code,
            stage = stage,
            modelId = modelId,
        )
    }

    private fun normalizeFailure(
        error: Throwable,
        code: EmbeddingRuntimeErrorCode,
        stage: EmbeddingRuntimeStage,
        modelId: String,
    ): EmbeddingRuntimeException {
        return EmbeddingRuntimeException.wrap(
            error = error,
            code = code,
            stage = stage,
            modelId = modelId,
        )
    }

    private fun runtimeState(
        status: String,
        reason: String,
        modelPath: String,
        vectorDimension: Int? = null,
        error: EmbeddingRuntimeException? = null,
    ): Map<String, Any?> {
        return mapOf(
            "status" to status,
            "reason" to reason,
            "vectorDimension" to vectorDimension,
            "errorCode" to error?.code?.wireName,
            "errorStage" to error?.stage?.wireName,
            "checkedAt" to clock(),
            "modelPath" to modelPath,
            "runtime" to "onnx",
            "supportsEmbedding" to (status == "ready"),
            "contextPackage" to contextPackage,
        )
    }
}
