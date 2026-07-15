package com.example.nssllama

import java.util.Locale

internal fun selectSilentRnLlamaLibrary(
    primaryAbi: String?,
    cpuFeatures: String,
): String? {
    if (!primaryAbi.equals("arm64-v8a", ignoreCase = true)) {
        return null
    }

    val features = cpuFeatures
        .lowercase(Locale.ROOT)
        .split(Regex("[^a-z0-9_]+"))
        .filterTo(mutableSetOf()) { it.isNotEmpty() }
    val hasFp16 = "fp16" in features || "fphp" in features
    val hasDotProduct = "dotprod" in features || "asimddp" in features
    val hasArmV8_2 = "asimd" in features && "crc32" in features && "aes" in features
    val hasArmV8_4 = "dcpop" in features && "uscat" in features

    return when {
        hasArmV8_4 && hasFp16 && hasDotProduct && "i8mm" in features ->
            "librnllama_v8_4_fp16_dotprod_i8mm.so"
        hasArmV8_4 && hasFp16 && hasDotProduct ->
            "librnllama_v8_4_fp16_dotprod.so"
        hasArmV8_2 && hasFp16 && hasDotProduct ->
            "librnllama_v8_2_fp16_dotprod.so"
        hasArmV8_2 && hasFp16 ->
            "librnllama_v8_2_fp16.so"
        else ->
            "librnllama_v8.so"
    }
}
