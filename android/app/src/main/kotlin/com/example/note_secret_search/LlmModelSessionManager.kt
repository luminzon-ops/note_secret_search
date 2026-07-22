package com.example.note_secret_search

class LlmModelSessionManager<T> {
    private var activeModelId: String? = null
    private var activeSession: T? = null

    fun get(modelId: String): T? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun install(modelId: String, session: T): T? {
        val previous = activeSession
        activeModelId = modelId
        activeSession = session
        return previous
    }

    fun take(modelId: String): T? {
        if (activeModelId != modelId) {
            return null
        }
        val previous = activeSession
        activeModelId = null
        activeSession = null
        return previous
    }

    fun takeAny(): T? {
        val previous = activeSession
        activeModelId = null
        activeSession = null
        return previous
    }

    fun replace(modelId: String, session: T, onDispose: (T) -> Unit) {
        val previous = install(modelId, session)
        if (previous != null) {
            onDispose(previous)
        }
    }

    fun release(modelId: String, onDispose: (T) -> Unit) {
        take(modelId)?.let(onDispose)
    }

    fun releaseAll(onDispose: (T) -> Unit) {
        takeAny()?.let(onDispose)
    }
}
