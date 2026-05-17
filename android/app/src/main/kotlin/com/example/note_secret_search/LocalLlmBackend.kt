package com.example.note_secret_search

import java.io.File

data class LocalLlmInspectResult(
    val supported: Boolean,
    val reason: String,
)

data class LocalLlmGenerateResult(
    val text: String,
    val finishReason: String,
)

data class LocalLlmGenerationConfig(
    val contextLength: Int = HUAWEI_SAFE_CONTEXT_LENGTH,
    val maxOutputTokens: Int = 96,
    val maxPromptChars: Int = 1200,
    val conservativeMode: Boolean = true,
    val emitPartialCompletion: Boolean = false,
    val temperature: Double = 0.7,
    val topK: Int = 40,
    val topP: Double = 0.9,
    val seed: Int = 42,
    val stopSequences: List<String> = listOf("</s>", "<|im_end|>", "<|endoftext|>"),
)

interface LocalLlmBackend {
    fun inspect(file: File): LocalLlmInspectResult
    fun load(modelId: String, file: File): LocalLlmBackendSession
    fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(maxOutputTokens = maxTokens),
    ): LocalLlmGenerateResult

    fun release(session: LocalLlmBackendSession)
}
