package com.example.note_secret_search

class LlmModelSessionManager<T> {
    private var activeModelId: String? = null
    private var activeSession: T? = null

    fun get(modelId: String): T? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun replace(modelId: String, session: T, onDispose: (T) -> Unit) {
        if (activeModelId != modelId) {
            activeSession?.let(onDispose)
        }
        activeModelId = modelId
        activeSession = session
    }

    fun release(modelId: String, onDispose: (T) -> Unit) {
        if (activeModelId == modelId) {
            activeSession?.let(onDispose)
            activeModelId = null
            activeSession = null
        }
    }

    fun releaseAll(onDispose: (T) -> Unit) {
        activeSession?.let(onDispose)
        activeModelId = null
        activeSession = null
    }
}
