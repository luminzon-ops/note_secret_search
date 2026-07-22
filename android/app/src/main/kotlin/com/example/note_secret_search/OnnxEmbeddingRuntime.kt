package com.example.note_secret_search

import android.content.Context
import java.io.File

fun interface EmbeddingTokenizerLoader {
    fun load(spec: OnnxEmbeddingModelSpec.TokenizerSpec): LoadedEmbeddingTokenizer
}

class OnnxEmbeddingRuntime(
    private val tokenizerLoader: EmbeddingTokenizerLoader,
    private val sessionManager: EmbeddingModelSessionManager,
    private val adapter: OnnxRuntimeAdapter,
    private val contextPackage: String,
    private val checksumVerifier: EmbeddingModelChecksumVerifier =
        Sha256EmbeddingModelChecksumVerifier(),
    private val executionSettings: OrtExecutionSettings = OrtExecutionSettings.controlled(),
    private val clock: () -> Long = System::currentTimeMillis,
) : EmbeddingRuntimeContract {
    private var cachedTokenizerSpec: OnnxEmbeddingModelSpec.TokenizerSpec? = null
    private var cachedTokenizer: LoadedEmbeddingTokenizer? = null

    constructor(
        context: Context,
        sessionManager: EmbeddingModelSessionManager,
    ) : this(
        tokenizerLoader = EmbeddingTokenizerLoader { spec ->
            val raw = context.assets
                .open("flutter_assets/${spec.assetPath}")
                .use { it.readBytes() }
            LoadedEmbeddingTokenizer(
                tokenizer = WordpieceEmbeddingTokenizer(
                    definition = TokenizerJsonParser.parse(
                        rawJson = raw.toString(Charsets.UTF_8),
                        expectedLowercase = spec.lowercase,
                    ),
                    maxSequenceLength = spec.maxSequenceLength,
                ),
                contentSha256 = sha256String(raw),
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
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        return try {
            val file = canonicalModelFile(modelId, modelPath)
            val actualChecksum = checksumVerifier.verify(
                file = file,
                expectedChecksum = verifiedChecksum,
                modelId = modelId,
            )
            val loadedTokenizer = loadTokenizer(modelId, spec.tokenizer)
            val identity = sessionIdentity(
                modelId = modelId,
                file = file,
                verifiedSha256 = actualChecksum,
                spec = spec,
                loadedTokenizer = loadedTokenizer,
            )
            openPreparedSession(file, identity, loadedTokenizer).use { prepared ->
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
                status = if (typed.code == EmbeddingRuntimeErrorCode.MODEL_MISSING) {
                    "missing"
                } else {
                    "degraded"
                },
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
        verifiedChecksum: String?,
    ): Map<String, Any?> {
        return try {
            val prepared = ensurePreparedSession(
                modelId = modelId,
                modelPath = modelPath,
                spec = spec,
                expectedChecksum = verifiedChecksum,
            )
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
                status = if (typed.code == EmbeddingRuntimeErrorCode.MODEL_MISSING) {
                    "missing"
                } else {
                    "degraded"
                },
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
        verifiedChecksum: String?,
        requestId: String?,
    ): Map<String, Any?> {
        if (text.isBlank()) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.INVALID_ARGUMENT,
                stage = EmbeddingRuntimeStage.ARGUMENT,
                modelId = modelId,
            )
        }

        return try {
            val prepared = ensurePreparedSession(
                modelId = modelId,
                modelPath = modelPath,
                spec = spec,
                expectedChecksum = verifiedChecksum,
            )
            sessionManager.run(
                identity = prepared.identity,
                requestId = requestId ?: "native-${clock()}",
            ) { active ->
                val encoded = active.tokenizer.encode(
                    text = text,
                    padToLength = active.contract.fixedSequenceLength,
                )
                val outputVector = runInference(
                    prepared = active,
                    encoded = encoded,
                    runtime = spec.runtime,
                    modelId = modelId,
                )
                mapOf(
                    "values" to outputVector,
                    "tokenCount" to encoded.attentionMask.count { it == 1L },
                    "vectorDimension" to outputVector.size,
                )
            }
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

    private fun ensurePreparedSession(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
        expectedChecksum: String?,
    ): PreparedEmbeddingSession {
        val file = canonicalModelFile(modelId, modelPath)
        val current = sessionManager.currentIdentity
        if (current != null && !current.matchesRequest(
                modelId = modelId,
                canonicalPath = file.path,
                expectedChecksum = expectedChecksum,
                spec = spec,
                settings = executionSettings,
            )
        ) {
            sessionManager.releaseAll()
        }
        if (!file.isFile || !file.canRead()) {
            sessionManager.releaseAll()
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.MODEL_MISSING,
                stage = EmbeddingRuntimeStage.MODEL_LOOKUP,
                modelId = modelId,
            )
        }

        sessionManager.currentIdentity?.let { identity ->
            if (identity.matchesRequest(
                    modelId = modelId,
                    canonicalPath = file.path,
                    expectedChecksum = expectedChecksum,
                    spec = spec,
                    settings = executionSettings,
                )
            ) {
                sessionManager.get(identity)?.let { return it }
            }
        }

        val actualChecksum = checksumVerifier.verify(
            file = file,
            expectedChecksum = expectedChecksum,
            modelId = modelId,
        )
        val loadedTokenizer = loadTokenizer(modelId, spec.tokenizer)
        val identity = sessionIdentity(
            modelId = modelId,
            file = file,
            verifiedSha256 = actualChecksum,
            spec = spec,
            loadedTokenizer = loadedTokenizer,
        )
        return sessionManager.getOrLoad(identity) {
            openPreparedSession(file, identity, loadedTokenizer)
        }
    }

    private fun openPreparedSession(
        file: File,
        identity: SessionIdentity,
        loadedTokenizer: LoadedEmbeddingTokenizer,
    ): PreparedEmbeddingSession {
        val handle = try {
            adapter.openSession(
                modelPath = file.path,
                settings = executionSettings,
            )
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.SESSION_LOAD,
                modelId = identity.modelId,
            )
        }
        return try {
            PreparedEmbeddingSession(
                identity = identity,
                tokenizer = loadedTokenizer.tokenizer,
                handle = handle,
                contract = ModelIoContractBuilder.build(
                    graph = handle.graph,
                    runtime = identity.runtimeSpec,
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
                modelId = identity.modelId,
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
            prepared.handle.run(inputs = inputs, outputName = contract.outputName)
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
    ): LoadedEmbeddingTokenizer {
        if (cachedTokenizerSpec == spec) {
            cachedTokenizer?.let { return it }
        }
        return try {
            tokenizerLoader.load(spec).also {
                cachedTokenizerSpec = spec
                cachedTokenizer = it
            }
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.TOKENIZER_SCHEMA_UNSUPPORTED,
                stage = EmbeddingRuntimeStage.TOKENIZER,
                modelId = modelId,
            )
        }
    }

    private fun sessionIdentity(
        modelId: String,
        file: File,
        verifiedSha256: String,
        spec: OnnxEmbeddingModelSpec,
        loadedTokenizer: LoadedEmbeddingTokenizer,
    ): SessionIdentity {
        return SessionIdentity(
            modelId = modelId,
            canonicalModelPath = file.path,
            verifiedSha256 = verifiedSha256,
            tokenizerSpec = spec.tokenizer,
            tokenizerJsonSha256 = loadedTokenizer.contentSha256,
            runtimeSpec = spec.runtime,
            executionSettings = executionSettings,
            runtimeImplementationVersion = RUNTIME_IMPLEMENTATION_VERSION,
        )
    }

    private fun canonicalModelFile(modelId: String, modelPath: String): File {
        return try {
            File(modelPath).canonicalFile
        } catch (error: Throwable) {
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.MODEL_MISSING,
                stage = EmbeddingRuntimeStage.MODEL_LOOKUP,
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
            message.startsWith("INVALID_OUTPUT:") ->
                EmbeddingRuntimeErrorCode.INVALID_OUTPUT
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

    private fun SessionIdentity.matchesRequest(
        modelId: String,
        canonicalPath: String,
        expectedChecksum: String?,
        spec: OnnxEmbeddingModelSpec,
        settings: OrtExecutionSettings,
    ): Boolean {
        return this.modelId == modelId &&
            canonicalModelPath == canonicalPath &&
            (expectedChecksum == null ||
                verifiedSha256.equals(expectedChecksum, ignoreCase = true)) &&
            tokenizerSpec == spec.tokenizer &&
            runtimeSpec == spec.runtime &&
            executionSettings == settings &&
            runtimeImplementationVersion == RUNTIME_IMPLEMENTATION_VERSION
    }

    companion object {
        private const val RUNTIME_IMPLEMENTATION_VERSION = 1
    }
}
