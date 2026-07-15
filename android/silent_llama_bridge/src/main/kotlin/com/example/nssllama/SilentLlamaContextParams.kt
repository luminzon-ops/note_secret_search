package com.example.nssllama

internal data class SilentLlamaInitArguments(
    val modelFd: Int,
    val embedding: Boolean,
    val contextSize: Int,
    val batchSize: Int,
    val threadCount: Int,
    val gpuLayerCount: Int,
    val useMlock: Boolean,
    val useMmap: Boolean,
    val vocabOnly: Boolean,
    val loraPath: String,
    val loraScale: Float,
    val ropeFrequencyBase: Float,
    val ropeFrequencyScale: Float,
)

internal data class SilentLlamaCompletionArguments(
    val prompt: String,
    val grammar: String,
    val temperature: Float,
    val threadCount: Int,
    val predictionCount: Int,
    val probabilityCount: Int,
    val penaltyLastN: Int,
    val penaltyRepeat: Float,
    val penaltyFrequency: Float,
    val penaltyPresence: Float,
    val mirostat: Float,
    val mirostatTau: Float,
    val mirostatEta: Float,
    val penalizeNewline: Boolean,
    val topK: Int,
    val topP: Float,
    val minP: Float,
    val xtcThreshold: Float,
    val xtcProbability: Float,
    val tailFreeSamplingZ: Float,
    val typicalP: Float,
    val seed: Int,
    val stop: Array<String>,
    val ignoreEos: Boolean,
    val logitBias: Array<DoubleArray>,
    val emitPartialCompletion: Boolean,
)

internal fun decodeSilentLlamaInitArguments(
    params: Map<String, Any>,
): SilentLlamaInitArguments {
    require(params.containsKey("model")) {
        "Missing required parameter: model"
    }
    return SilentLlamaInitArguments(
        modelFd = params["model_fd"] as Int,
        embedding = params.booleanValue("embedding", false),
        contextSize = params.intValue("n_ctx", 512),
        batchSize = params.intValue("n_batch", 512),
        threadCount = params.intValue("n_threads", 0),
        gpuLayerCount = params.intValue("n_gpu_layers", 0),
        useMlock = params.booleanValue("use_mlock", true),
        useMmap = params.booleanValue("use_mmap", true),
        vocabOnly = params.booleanValue("vocab_only", false),
        loraPath = params["lora"] as? String ?: "",
        loraScale = params.floatValue("lora_scaled", 1.0f),
        ropeFrequencyBase = params.floatValue("rope_freq_base", 0.0f),
        ropeFrequencyScale = params.floatValue("rope_freq_scale", 0.0f),
    )
}

internal fun decodeSilentLlamaCompletionArguments(
    params: Map<String, Any>,
): SilentLlamaCompletionArguments {
    require(params.containsKey("prompt")) {
        "Missing required parameter: prompt"
    }
    return SilentLlamaCompletionArguments(
        prompt = params["prompt"] as String,
        grammar = params["grammar"] as? String ?: "",
        temperature = params.floatValue("temperature", 0.7f),
        threadCount = params.intValue("n_threads", 0),
        predictionCount = params.intValue("n_predict", -1),
        probabilityCount = params.intValue("n_probs", 0),
        penaltyLastN = params.intValue("penalty_last_n", 64),
        penaltyRepeat = params.floatValue("penalty_repeat", 1.0f),
        penaltyFrequency = params.floatValue("penalty_freq", 0.0f),
        penaltyPresence = params.floatValue("penalty_present", 0.0f),
        mirostat = params.floatValue("mirostat", 0.0f),
        mirostatTau = params.floatValue("mirostat_tau", 5.0f),
        mirostatEta = params.floatValue("mirostat_eta", 0.1f),
        penalizeNewline = params.booleanValue("penalize_nl", false),
        topK = params.intValue("top_k", 40),
        topP = params.floatValue("top_p", 0.95f),
        minP = params.floatValue("min_p", 0.05f),
        xtcThreshold = params.floatValue("xtc_t", 0.0f),
        xtcProbability = params.floatValue("xtc_p", 0.0f),
        tailFreeSamplingZ = params.floatValue("tfs_z", 1.0f),
        typicalP = params.floatValue("typical_p", 1.0f),
        seed = params.intValue("seed", -1),
        stop = params.stringArray("stop"),
        ignoreEos = params.booleanValue("ignore_eos", false),
        logitBias = params.doubleArrayMatrix("logit_bias"),
        emitPartialCompletion = params.booleanValue(
            "emit_partial_completion",
            false,
        ),
    )
}

private fun Map<String, Any>.booleanValue(
    key: String,
    defaultValue: Boolean,
): Boolean = this[key] as? Boolean ?: defaultValue

private fun Map<String, Any>.intValue(
    key: String,
    defaultValue: Int,
): Int = this[key] as? Int ?: defaultValue

private fun Map<String, Any>.floatValue(
    key: String,
    defaultValue: Float,
): Float = (this[key] as? Double)?.toFloat() ?: defaultValue

private fun Map<String, Any>.stringArray(key: String): Array<String> {
    return (this[key] as? List<*>)
        ?.map { it as String }
        ?.toTypedArray()
        ?: emptyArray()
}

private fun Map<String, Any>.doubleArrayMatrix(
    key: String,
): Array<DoubleArray> {
    return (this[key] as? List<*>)
        ?.map { row ->
            (row as List<*>)
                .map { it as Double }
                .toDoubleArray()
        }
        ?.toTypedArray()
        ?: emptyArray()
}
