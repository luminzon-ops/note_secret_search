package com.example.note_secret_search

fun runEmbeddingInference(
    prepared: PreparedEmbeddingSession,
    encoded: EncodedEmbeddingInput,
    runtime: OnnxEmbeddingModelSpec.RuntimeSpec,
    modelId: String,
    cancellation: CancellationHandle,
): List<Double> {
    cancellation.throwIfCancelled(modelId)
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
            cancellation = cancellation,
        )
    } catch (error: Throwable) {
        throw classifyEmbeddingInferenceFailure(error, modelId, cancellation)
    }
    cancellation.throwIfCancelled(modelId)
    return try {
        val decoded = EmbeddingTensorDecoder.decode(output)
        val actualVectorDimension = when (decoded.kind) {
            EmbeddingTensorKind.TOKEN -> decoded.tokenVectors.first().size
            EmbeddingTensorKind.SENTENCE -> decoded.sentenceVector.size
        }
        require(actualVectorDimension == contract.vectorDimension) {
            "INVALID_OUTPUT: embedding output dimension changed after session inspection"
        }
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
        cancellation.throwIfCancelled(modelId)
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

private fun classifyEmbeddingInferenceFailure(
    error: Throwable,
    modelId: String,
    cancellation: CancellationHandle,
): EmbeddingRuntimeException {
    cancellation.errorOrNull(modelId)?.let { return it }
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
