package com.example.note_secret_search

data class PreparedEmbeddingSession(
    val handle: OnnxSessionHandle,
    val contract: ModelIoContract,
) : AutoCloseable {
    override fun close() {
        handle.close()
    }
}

class EmbeddingModelSessionManager {
    private var activeModelId: String? = null
    private var activeSession: PreparedEmbeddingSession? = null

    fun get(modelId: String): PreparedEmbeddingSession? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun replace(modelId: String, session: PreparedEmbeddingSession) {
        if (activeModelId != modelId) {
            activeSession?.close()
        }
        activeModelId = modelId
        activeSession = session
    }

    fun release(modelId: String) {
        if (activeModelId == modelId) {
            activeSession?.close()
            activeSession = null
            activeModelId = null
        }
    }

    fun releaseAll() {
        activeSession?.close()
        activeSession = null
        activeModelId = null
    }
}
