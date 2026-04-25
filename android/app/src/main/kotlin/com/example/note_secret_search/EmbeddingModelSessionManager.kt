package com.example.note_secret_search

import ai.onnxruntime.OrtSession

class EmbeddingModelSessionManager {
    private var activeModelId: String? = null
    private var activeSession: OrtSession? = null

    fun get(modelId: String): OrtSession? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun replace(modelId: String, session: OrtSession) {
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
