package com.example.note_secret_search

import android.content.Context
import android.os.Build
import java.io.File

interface LlmBackendFactoryContract {
    fun create(file: File): LocalLlmBackend?
}

class LlmBackendFactory(
    private val context: Context,
) : LlmBackendFactoryContract {
    override fun create(file: File): LocalLlmBackend? {
        val extension = file.extension.lowercase()
        return when (extension) {
            "gguf" -> createGatedGgufBackend(
                manufacturer = Build.MANUFACTURER,
                supportedAbis = Build.SUPPORTED_ABIS.toList(),
                hasHuaweiSafeVariant = HAS_HUAWEI_SAFE_GGUF_VARIANT,
            ) {
                GgufLlamaCppBackend(context)
            }
            else -> null
        }
    }
}

internal fun <T> createGatedGgufBackend(
    manufacturer: String,
    supportedAbis: List<String>,
    hasHuaweiSafeVariant: Boolean = false,
    createBackend: () -> T,
): T? {
    if (!supportsPackagedLlmRuntime(supportedAbis)) {
        return null
    }
    if (shouldBlockGgufBackend(manufacturer, hasHuaweiSafeVariant)) {
        return null
    }
    return createBackend()
}

internal fun supportsPackagedLlmRuntime(supportedAbis: List<String>): Boolean {
    return supportedAbis.any {
        it.trim().equals(PACKAGED_LLM_ABI, ignoreCase = true)
    }
}

/**
 * Returns true if GGUF backend should be blocked for the given manufacturer,
 * because Huawei devices crash in the native llama.cpp GGUF backend.
 *
 * @param manufacturer The device manufacturer string (e.g. Build.MANUFACTURER).
 * @param hasHuaweiSafeVariant True when the app is bundled with a Huawei-safe
 * native GGUF variant and Huawei/Honor should be allowed for device validation.
 * @return true to block GGUF backend creation (Huawei devices), false to allow it.
 */
internal fun shouldBlockGgufBackend(
    manufacturer: String,
    hasHuaweiSafeVariant: Boolean = false,
): Boolean {
    val isHuaweiFamily = manufacturer.trim().equals("huawei", ignoreCase = true) ||
        manufacturer.trim().equals("honor", ignoreCase = true)
    return isHuaweiFamily && !hasHuaweiSafeVariant
}

internal const val HAS_HUAWEI_SAFE_GGUF_VARIANT = true
internal const val PACKAGED_LLM_ABI = "arm64-v8a"
