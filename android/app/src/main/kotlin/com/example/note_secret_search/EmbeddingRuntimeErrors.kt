package com.example.note_secret_search

enum class EmbeddingRuntimeErrorCode(val wireName: String) {
    INVALID_ARGUMENT("INVALID_ARGUMENT"),
    MODEL_MISSING("MODEL_MISSING"),
    CHECKSUM_MISMATCH("CHECKSUM_MISMATCH"),
    TOKENIZER_SCHEMA_UNSUPPORTED("TOKENIZER_SCHEMA_UNSUPPORTED"),
    MODEL_SCHEMA_UNSUPPORTED("MODEL_SCHEMA_UNSUPPORTED"),
    INVALID_OUTPUT("INVALID_OUTPUT"),
    BUSY("BUSY"),
    CANCELLED("CANCELLED"),
    RUNTIME_CLOSED("RUNTIME_CLOSED"),
    ORT_FAILURE("ORT_FAILURE"),
}

enum class EmbeddingRuntimeStage(val wireName: String) {
    ARGUMENT("argument"),
    MODEL_LOOKUP("model_lookup"),
    CHECKSUM("checksum"),
    TOKENIZER("tokenizer"),
    SESSION_LOAD("session_load"),
    MODEL_SCHEMA("model_schema"),
    INFERENCE("inference"),
    OUTPUT("output"),
    QUEUE("queue"),
    LIFECYCLE("lifecycle"),
}

class EmbeddingRuntimeException(
    val code: EmbeddingRuntimeErrorCode,
    val stage: EmbeddingRuntimeStage,
    val modelId: String? = null,
    cause: Throwable? = null,
) : RuntimeException(code.wireName, cause) {
    fun withModelId(modelId: String?): EmbeddingRuntimeException {
        return if (this.modelId != null || modelId == null) {
            this
        } else {
            EmbeddingRuntimeException(
                code = code,
                stage = stage,
                modelId = modelId,
                cause = cause,
            )
        }
    }

    companion object {
        fun wrap(
            error: Throwable,
            code: EmbeddingRuntimeErrorCode,
            stage: EmbeddingRuntimeStage,
            modelId: String? = null,
        ): EmbeddingRuntimeException {
            return if (error is EmbeddingRuntimeException) {
                error.withModelId(modelId)
            } else {
                EmbeddingRuntimeException(
                    code = code,
                    stage = stage,
                    modelId = modelId,
                    cause = error,
                )
            }
        }
    }
}
