package com.example.note_secret_search

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File

interface LocalLlmRuntimeContract {
    fun inspectModel(modelId: String, modelPath: String): Map<String, Any?>

    fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?>

    fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig = LocalLlmGenerationConfig(),
    ): Map<String, Any?>

    fun releaseModel(modelId: String)
}

class LocalLlmRuntime(
    private val packageName: String,
    private val sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    private val backendFactory: LlmBackendFactoryContract,
) : LocalLlmRuntimeContract {
    constructor(
        context: Context,
        sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
    ) : this(
        packageName = context.packageName,
        sessionManager = sessionManager,
        backendFactory = LlmBackendFactory(context),
    )

    override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
        logInfo("inspectModel start modelId=$modelId path=$modelPath")
        val file = File(modelPath)
        if (!file.exists()) {
            logWarning("inspectModel missing file modelId=$modelId path=$modelPath")
            return runtimeState(
                status = "missing",
                reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
                runtime = "none",
            )
        }

        val backend = backendFactory.create(file)
            ?: return runtimeState(
                status = "degraded",
                reason = "当前模型格式暂无可用 Android 本地推理 backend。",
                modelPath = modelPath,
                runtime = "unsupported",
            )

        val inspect = backend.inspect(file)
        logInfo("inspectModel backend inspect modelId=$modelId supported=${inspect.supported} reason=${inspect.reason}")
        if (!inspect.supported) {
            return runtimeState(
                status = "degraded",
                reason = inspect.reason,
                modelPath = modelPath,
                runtime = "unsupported",
            )
        }

        val activeSession = sessionManager.get(modelId)
        if (activeSession != null && activeSession.modelPath == file.absolutePath) {
            logInfo("inspectModel ready-from-session modelId=$modelId backend=${activeSession.backendName}")
            return runtimeState(
                status = "ready",
                reason = "本地 LLM runtime 已就绪。",
                modelPath = modelPath,
                runtime = activeSession.backendName,
            )
        }

        logInfo("inspectModel installed_unverified modelId=$modelId")
        return runtimeState(
            status = "installed_unverified",
            reason = inspect.reason,
            modelPath = modelPath,
            runtime = "candidate",
        )
    }

    override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
        logInfo("ensureModelReady start modelId=$modelId path=$modelPath")
        logDeviceFingerprint()
        val file = File(modelPath)
        if (!file.exists()) {
            logWarning("ensureModelReady missing file modelId=$modelId path=$modelPath")
            return runtimeState(
                status = "missing",
                reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
                modelPath = modelPath,
                runtime = "none",
            )
        }

        // Check for existing session BEFORE creating a fresh backend.
        // This prevents allocating a new backend instance when the session
        // (and its associated backend) is already alive.
        val existingSession = sessionManager.get(modelId)
        if (
            existingSession != null &&
            existingSession.modelPath == file.absolutePath
        ) {
            logInfo("ensureModelReady reusing existing session modelId=$modelId backend=${existingSession.backendName}")
            return runtimeState(
                status = "ready",
                reason = "本地 LLM runtime 已就绪。",
                modelPath = modelPath,
                runtime = existingSession.backendName,
            )
        }

        // Release any existing session with a mismatched modelPath before loading fresh.
        // LlmModelSessionManager.replace() skips release when modelId matches (same-modelId reuse),
        // so we must explicitly release here when modelPath differs.
        if (existingSession != null) {
            sessionManager.release(modelId) { old ->
                old.backend.release(old)
            }
        }

        val backend = backendFactory.create(file)
            ?: return runtimeState(
                status = "degraded",
                reason = "当前模型格式暂无可用 Android 本地推理 backend。",
                modelPath = modelPath,
                runtime = "unsupported",
            )

        return try {
            val session = backend.load(modelId, file).also { created ->
                logInfo("ensureModelReady loaded session modelId=$modelId backend=${created.backendName}")
            }
            sessionManager.replace(modelId, session) { old ->
                old.backend.release(old)
            }

            logInfo("ensureModelReady ready-after-load modelId=$modelId backend=${session.backendName}")
            runtimeState(
                status = "ready",
                reason = "本地 LLM runtime 已加载完成，可在首轮请求中执行真实生成。",
                modelPath = modelPath,
                runtime = session.backendName,
            )
        } catch (error: Throwable) {
            sessionManager.release(modelId) { existing ->
                try {
                    existing.backend.release(existing)
                } catch (_: Throwable) {
                }
            }
            logError("ensureModelReady degraded modelId=$modelId error=${error.message}", error)
            runtimeState(
                status = "degraded",
                reason = "模型已安装但当前加载失败：${error.message ?: "unknown error"}",
                modelPath = modelPath,
                runtime = "failed",
            )
        }
    }

    override fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
    ): Map<String, Any?> {
        require(prompt.isNotBlank()) { "Prompt must not be blank." }

        val failedWhileReusingExistingSession =
            sessionManager.get(modelId)?.modelPath == File(modelPath).absolutePath

        return try {
            generateTextOnce(
                modelId = modelId,
                modelPath = modelPath,
                prompt = prompt,
                usedPrivateContext = usedPrivateContext,
                config = config,
            )
        } catch (error: Throwable) {
            releaseSessionQuietly(modelId)
            if (failedWhileReusingExistingSession) {
                logWarning(
                    "generateText released stale session after reused-session failure modelId=$modelId error=${error.message}",
                )
            }

            throw IllegalStateException(error.message ?: "Local LLM generation failed.")
        }
    }

    private fun generateTextOnce(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
        config: LocalLlmGenerationConfig,
    ): Map<String, Any?> {
        val ready = ensureModelReady(modelId, modelPath)
        if (ready["status"] != "ready") {
            throw IllegalStateException(ready["reason"] as? String ?: "LLM runtime is not ready.")
        }

        val session = sessionManager.get(modelId)
            ?: throw IllegalStateException("LLM session was not prepared.")

        session.hasEnteredGenerationLifecycle = true
        val result = session.backend.generate(
            session = session,
            prompt = prompt.trim(),
            maxTokens = config.maxOutputTokens,
            config = config,
        )
        return mapOf(
            "text" to result.text,
            "finishReason" to result.finishReason,
            "usedPrivateContext" to usedPrivateContext,
            "status" to "ready",
            "reason" to "本地 LLM runtime 已完成真实生成。",
            "checkedAt" to System.currentTimeMillis(),
            "modelPath" to modelPath,
            "runtime" to session.backendName,
            "contextPackage" to packageName,
        )
    }

    override fun releaseModel(modelId: String) {
        val session = sessionManager.get(modelId) ?: return
        sessionManager.release(modelId) { existing -> existing.backend.release(existing) }
    }

    private fun runtimeState(
        status: String,
        reason: String,
        modelPath: String,
        runtime: String,
    ): Map<String, Any?> {
        return mapOf(
            "ready" to (status == "ready"),
            "status" to status,
            "reason" to reason,
            "checkedAt" to System.currentTimeMillis(),
            "modelPath" to modelPath,
            "runtime" to runtime,
            "supportsGeneration" to (status == "ready"),
            "contextPackage" to packageName,
        )
    }

    private fun releaseSessionQuietly(modelId: String) {
        sessionManager.release(modelId) { existing ->
            try {
                existing.backend.release(existing)
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "LocalLlmRuntime"
    }

    private fun logInfo(message: String) {
        runLoggingSafely { Log.i(TAG, message) }
    }

    private fun logWarning(message: String) {
        runLoggingSafely { Log.w(TAG, message) }
    }

    private fun logError(message: String, error: Throwable) {
        runLoggingSafely { Log.e(TAG, message, error) }
    }

    private inline fun runLoggingSafely(block: () -> Unit) {
        try {
            block()
        } catch (_: RuntimeException) {
        }
    }

    private fun logDeviceFingerprint() {
        runLoggingSafely {
            val manufacturer = runCatching { Build.MANUFACTURER }.getOrNull() ?: "unknown"
            val model = runCatching { Build.MODEL }.getOrNull() ?: "unknown"
            val sdkInt = runCatching { Build.VERSION.SDK_INT }.getOrNull() ?: -1
            val release = runCatching { Build.VERSION.RELEASE }.getOrNull() ?: "unknown"
            val abis = runCatching { Build.SUPPORTED_ABIS?.joinToString(",") }.getOrNull() ?: "unknown"
            Log.i(
                TAG,
                "device fingerprint manufacturer=$manufacturer model=$model " +
                    "sdk=$sdkInt release=$release abis=$abis",
            )
        }
    }
}
