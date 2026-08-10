package com.example.note_secret_search

enum class LlmRuntimeErrorCode(val wireName: String) {
    INVALID_ARGUMENT("INVALID_ARGUMENT"),
    MODEL_MISSING("MODEL_MISSING"),
    MODEL_UNSUPPORTED("MODEL_UNSUPPORTED"),
    BUSY("BUSY"),
    CANCELLED("CANCELLED"),
    LOAD_FAILED("LOAD_FAILED"),
    GENERATION_FAILED("GENERATION_FAILED"),
    RELEASE_FAILED("RELEASE_FAILED"),
    RUNTIME_CLOSED("RUNTIME_CLOSED"),
}

enum class LlmRuntimeStage(val wireName: String) {
    ARGUMENT("argument"),
    MODEL_LOOKUP("model_lookup"),
    SESSION_LOAD("session_load"),
    GENERATION("generation"),
    CANCELLATION("cancellation"),
    RELEASE("release"),
    LIFECYCLE("lifecycle"),
}

class LlmRuntimeException(
    val code: LlmRuntimeErrorCode,
    val stage: LlmRuntimeStage,
    val modelId: String? = null,
    val requestId: String? = null,
    cause: Throwable? = null,
) : RuntimeException(code.wireName, cause) {
    fun withModelId(value: String?): LlmRuntimeException {
        return if (modelId != null || value == null) {
            this
        } else {
            copy(modelId = value)
        }
    }

    fun withRequestId(value: String?): LlmRuntimeException {
        return if (requestId != null || value == null) {
            this
        } else {
            copy(requestId = value)
        }
    }

    private fun copy(
        code: LlmRuntimeErrorCode = this.code,
        stage: LlmRuntimeStage = this.stage,
        modelId: String? = this.modelId,
        requestId: String? = this.requestId,
    ): LlmRuntimeException {
        return LlmRuntimeException(
            code = code,
            stage = stage,
            modelId = modelId,
            requestId = requestId,
            cause = cause,
        )
    }

    companion object {
        fun wrap(
            error: Throwable,
            code: LlmRuntimeErrorCode,
            stage: LlmRuntimeStage,
            modelId: String? = null,
            requestId: String? = null,
        ): LlmRuntimeException {
            return if (error is LlmRuntimeException) {
                error.withModelId(modelId).withRequestId(requestId)
            } else {
                LlmRuntimeException(
                    code = code,
                    stage = stage,
                    modelId = modelId,
                    requestId = requestId,
                    cause = error,
                )
            }
        }
    }
}
