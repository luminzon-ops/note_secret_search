package com.example.nssllama

import android.os.Build
import androidx.annotation.Keep
import java.io.File

@Keep
class SilentLlamaContext(
    val id: Int,
    params: Map<String, Any>,
) {
    private var tokenCallback: ((String) -> Unit)? = null

    val context: Long
    val modelDetails: Map<String, Any?>

    init {
        SilentLlamaNativeLoader.ensureLoaded()
        val arguments = decodeSilentLlamaInitArguments(params)
        context = initContextWithFd(
            modelFd = arguments.modelFd,
            embedding = arguments.embedding,
            contextSize = arguments.contextSize,
            batchSize = arguments.batchSize,
            threadCount = arguments.threadCount,
            gpuLayerCount = arguments.gpuLayerCount,
            useMlock = arguments.useMlock,
            useMmap = arguments.useMmap,
            vocabOnly = arguments.vocabOnly,
            loraPath = arguments.loraPath,
            loraScale = arguments.loraScale,
            ropeFrequencyBase = arguments.ropeFrequencyBase,
            ropeFrequencyScale = arguments.ropeFrequencyScale,
        )
        modelDetails = loadModelDetails(context).toMutableMap()
    }

    fun setTokenCallback(callback: (String) -> Unit) {
        tokenCallback = callback
    }

    fun completion(params: Map<String, Any>): Map<String, Any?> {
        val arguments = decodeSilentLlamaCompletionArguments(params)
        val result = doCompletion(
            context = context,
            prompt = arguments.prompt,
            grammar = arguments.grammar,
            temperature = arguments.temperature,
            threadCount = arguments.threadCount,
            predictionCount = arguments.predictionCount,
            probabilityCount = arguments.probabilityCount,
            penaltyLastN = arguments.penaltyLastN,
            penaltyRepeat = arguments.penaltyRepeat,
            penaltyFrequency = arguments.penaltyFrequency,
            penaltyPresence = arguments.penaltyPresence,
            mirostat = arguments.mirostat,
            mirostatTau = arguments.mirostatTau,
            mirostatEta = arguments.mirostatEta,
            penalizeNewline = arguments.penalizeNewline,
            topK = arguments.topK,
            topP = arguments.topP,
            minP = arguments.minP,
            xtcThreshold = arguments.xtcThreshold,
            xtcProbability = arguments.xtcProbability,
            tailFreeSamplingZ = arguments.tailFreeSamplingZ,
            typicalP = arguments.typicalP,
            seed = arguments.seed,
            stop = arguments.stop,
            ignoreEos = arguments.ignoreEos,
            logitBias = arguments.logitBias,
            callback = PartialCompletionCallback(
                emitNeeded = arguments.emitPartialCompletion,
            ),
        ).toMutableMap()
        if (result.containsKey("error")) {
            throw IllegalStateException(result["error"] as String)
        }
        return result
    }

    fun stopCompletion() {
        stopCompletion(context)
    }

    fun release() {
        freeContext(context)
    }

    @Keep
    inner class PartialCompletionCallback(
        private val emitNeeded: Boolean,
    ) {
        @Keep
        fun onPartialCompletion(tokenResult: Map<String, Any?>) {
            if (!emitNeeded) {
                return
            }
            tokenCallback?.invoke(tokenResult["token"] as String)
        }
    }

    private external fun initContextWithFd(
        modelFd: Int,
        embedding: Boolean,
        contextSize: Int,
        batchSize: Int,
        threadCount: Int,
        gpuLayerCount: Int,
        useMlock: Boolean,
        useMmap: Boolean,
        vocabOnly: Boolean,
        loraPath: String,
        loraScale: Float,
        ropeFrequencyBase: Float,
        ropeFrequencyScale: Float,
    ): Long

    private external fun loadModelDetails(context: Long): Map<String, Any?>

    private external fun doCompletion(
        context: Long,
        prompt: String,
        grammar: String,
        temperature: Float,
        threadCount: Int,
        predictionCount: Int,
        probabilityCount: Int,
        penaltyLastN: Int,
        penaltyRepeat: Float,
        penaltyFrequency: Float,
        penaltyPresence: Float,
        mirostat: Float,
        mirostatTau: Float,
        mirostatEta: Float,
        penalizeNewline: Boolean,
        topK: Int,
        topP: Float,
        minP: Float,
        xtcThreshold: Float,
        xtcProbability: Float,
        tailFreeSamplingZ: Float,
        typicalP: Float,
        seed: Int,
        stop: Array<String>,
        ignoreEos: Boolean,
        logitBias: Array<DoubleArray>,
        callback: PartialCompletionCallback,
    ): Map<String, Any?>

    private external fun stopCompletion(context: Long)

    private external fun freeContext(context: Long)
}

@Keep
private object SilentLlamaNativeLoader {
    init {
        System.loadLibrary("silent_llama_bridge")
        val libraryName = selectSilentRnLlamaLibrary(
            primaryAbi = Build.SUPPORTED_ABIS.firstOrNull(),
            cpuFeatures = readCpuFeatures(),
        ) ?: throw UnsatisfiedLinkError(
            "No supported rnllama library is available for this device.",
        )
        loadRnLlamaLibrary(libraryName)
    }

    fun ensureLoaded() = Unit

    private external fun loadRnLlamaLibrary(libraryName: String)

    private fun readCpuFeatures(): String {
        return try {
            File("/proc/cpuinfo").useLines { lines ->
                lines.firstOrNull { line ->
                    line
                        .substringBefore(':')
                        .trim()
                        .equals("Features", ignoreCase = true)
                }.orEmpty()
            }
        } catch (_: Throwable) {
            ""
        }
    }
}
