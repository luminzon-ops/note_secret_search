package com.example.note_secret_search

interface MultimodalLlmRuntimeContract {
    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
    ): Map<String, Any?>

    fun generateMultimodalText(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
        reasoningEnabled: Boolean,
    ): Map<String, Any?>
}

// Replacement point for real MiniCPM-V inference: inject a MultimodalLlmRuntimeContract
// implementation into LlmRuntimePlugin that uses llama.cpp's mtmd/vision path. The backend
// must load both modelPath and mmprojPath, consume imagePath, and keep reasoningEnabled=false
// for MiniCPM-V 4.6 unless a future model explicitly supports reasoning.
class FallbackMultimodalLlmRuntime : MultimodalLlmRuntimeContract {
    override fun ensureModelReady(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
    ): Map<String, Any?> {
        if (mmprojPath.isBlank()) {
            return mapOf(
                "status" to "missing_mmproj",
                "ready" to false,
                "backend" to "fallback_no_mtmd",
                "message" to "MiniCPM-V 视觉投影文件缺失，请重新下载。",
            )
        }
        return mapOf(
            "status" to "runtime_unavailable",
            "ready" to false,
            "backend" to "fallback_no_mtmd",
            "message" to "当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。",
        )
    }

    override fun generateMultimodalText(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
        reasoningEnabled: Boolean,
    ): Map<String, Any?> {
        return ensureModelReady(
            modelId = modelId,
            modelPath = modelPath,
            mmprojPath = mmprojPath,
        )
    }
}
