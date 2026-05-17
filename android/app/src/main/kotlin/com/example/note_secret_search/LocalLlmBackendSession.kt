package com.example.note_secret_search

data class LocalLlmBackendSession(
    val modelId: String,
    val modelPath: String,
    val backendName: String,
    val handle: Any,
    val backend: LocalLlmBackend,
    var hasEnteredGenerationLifecycle: Boolean = false,
)
