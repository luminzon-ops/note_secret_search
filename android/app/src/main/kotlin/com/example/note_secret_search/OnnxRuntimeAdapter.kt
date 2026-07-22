package com.example.note_secret_search

import ai.onnxruntime.NodeInfo
import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.nio.IntBuffer
import java.nio.LongBuffer
import kotlin.math.min

data class OrtExecutionSettings(
    val interOpThreads: Int,
    val intraOpThreads: Int,
    val strategyVersion: Int = 1,
) {
    init {
        require(interOpThreads > 0)
        require(intraOpThreads > 0)
        require(strategyVersion > 0)
    }

    companion object {
        fun controlled(
            availableProcessors: Int = Runtime.getRuntime().availableProcessors(),
        ): OrtExecutionSettings {
            return OrtExecutionSettings(
                interOpThreads = 1,
                intraOpThreads = min(2, availableProcessors.coerceAtLeast(1)),
            )
        }
    }
}

data class IntegralTensorData(
    val type: IntegralTensorType,
    val shape: LongArray,
    val values: LongArray,
) {
    init {
        require(shape.contentEquals(longArrayOf(1, values.size.toLong()))) {
            "MODEL_SCHEMA_UNSUPPORTED: integral input shape does not match values"
        }
    }
}

data class FloatTensorData(
    val shape: LongArray,
    val values: FloatArray,
) {
    companion object {
        fun fromDecoded(decoded: DecodedEmbeddingTensor): FloatTensorData {
            return when (decoded.kind) {
                EmbeddingTensorKind.SENTENCE -> FloatTensorData(
                    shape = longArrayOf(1, decoded.sentenceVector.size.toLong()),
                    values = decoded.sentenceVector.copyOf(),
                )

                EmbeddingTensorKind.TOKEN -> {
                    val width = decoded.tokenVectors.firstOrNull()?.size ?: 0
                    val values = FloatArray(decoded.tokenVectors.size * width)
                    decoded.tokenVectors.forEachIndexed { rowIndex, row ->
                        row.copyInto(values, destinationOffset = rowIndex * width)
                    }
                    FloatTensorData(
                        shape = longArrayOf(1, decoded.tokenVectors.size.toLong(), width.toLong()),
                        values = values,
                    )
                }
            }
        }
    }
}

interface OnnxRuntimeAdapter {
    fun openSession(
        modelPath: String,
        settings: OrtExecutionSettings,
        cancellation: CancellationHandle = CancellationHandle(),
    ): OnnxSessionHandle
}

interface OnnxSessionHandle : AutoCloseable {
    val graph: ModelGraphInfo

    fun run(
        inputs: Map<String, IntegralTensorData>,
        outputName: String,
        cancellation: CancellationHandle = CancellationHandle(),
    ): FloatTensorData
}

class OrtOnnxRuntimeAdapter(
    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment(),
) : OnnxRuntimeAdapter {
    override fun openSession(
        modelPath: String,
        settings: OrtExecutionSettings,
        cancellation: CancellationHandle,
    ): OnnxSessionHandle {
        cancellation.throwIfCancelled()
        val options = OrtSession.SessionOptions()
        return try {
            options.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
            options.setInterOpNumThreads(settings.interOpThreads)
            options.setIntraOpNumThreads(settings.intraOpThreads)
            val session = environment.createSession(modelPath, options)
            try {
                cancellation.throwIfCancelled()
                OrtOnnxSessionHandle(
                    environment = environment,
                    session = session,
                )
            } catch (error: Throwable) {
                session.close()
                throw error
            }
        } finally {
            options.close()
        }
    }
}

private class OrtOnnxSessionHandle(
    private val environment: OrtEnvironment,
    private val session: OrtSession,
) : OnnxSessionHandle {
    override val graph: ModelGraphInfo = ModelGraphInfo(
        inputs = session.inputInfo.toModelTensorInfo(),
        outputs = session.outputInfo.toModelTensorInfo(),
    )

    private var closed = false

    override fun run(
        inputs: Map<String, IntegralTensorData>,
        outputName: String,
        cancellation: CancellationHandle,
    ): FloatTensorData {
        cancellation.throwIfCancelled()
        val tensors = linkedMapOf<String, OnnxTensor>()
        try {
            inputs.forEach { (name, input) ->
                cancellation.throwIfCancelled()
                tensors[name] = when (input.type) {
                    IntegralTensorType.INT64 -> OnnxTensor.createTensor(
                        environment,
                        LongBuffer.wrap(input.values),
                        input.shape,
                    )

                    IntegralTensorType.INT32 -> {
                        val values = IntArray(input.values.size) { index ->
                            input.values[index].also {
                                require(it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
                                    "MODEL_SCHEMA_UNSUPPORTED: INT32 input value is out of range"
                                }
                            }.toInt()
                        }
                        OnnxTensor.createTensor(
                            environment,
                            IntBuffer.wrap(values),
                            input.shape,
                        )
                    }
                }
            }

            OrtSession.RunOptions().use { runOptions ->
                cancellation.registerTerminator {
                    runOptions.setTerminate(true)
                }.use {
                    cancellation.throwIfCancelled()
                    try {
                        session.run(tensors, setOf(outputName), runOptions).use { result ->
                            cancellation.throwIfCancelled()
                            val selected = result.get(outputName).orElseThrow {
                                IllegalArgumentException(
                                    "INVALID_OUTPUT: configured embedding output was not returned",
                                )
                            }
                            val info = selected.info as? TensorInfo
                                ?: throw IllegalArgumentException(
                                    "INVALID_OUTPUT: embedding output is not a tensor",
                                )
                            val decoded = EmbeddingTensorDecoder.decode(
                                type = info.type.toModelTensorType(),
                                shape = info.shape,
                                value = selected.value,
                            )
                            cancellation.throwIfCancelled()
                            return FloatTensorData.fromDecoded(decoded)
                        }
                    } catch (error: Throwable) {
                        cancellation.throwIfCancelled()
                        throw error
                    }
                }
            }
        } finally {
            tensors.values.forEach(OnnxTensor::close)
        }
    }

    override fun close() {
        if (!closed) {
            closed = true
            session.close()
        }
    }
}

private fun Map<String, NodeInfo>.toModelTensorInfo(): Map<String, ModelTensorInfo> {
    return mapValues { (_, node) ->
        val info = node.info as? TensorInfo
            ?: return@mapValues ModelTensorInfo(
                type = ModelTensorType.UNSUPPORTED,
                shape = longArrayOf(),
            )
        ModelTensorInfo(
            type = info.type.toModelTensorType(),
            shape = info.shape.copyOf(),
        )
    }
}

private fun OnnxJavaType.toModelTensorType(): ModelTensorType {
    return when (this) {
        OnnxJavaType.FLOAT -> ModelTensorType.FLOAT
        OnnxJavaType.INT32 -> ModelTensorType.INT32
        OnnxJavaType.INT64 -> ModelTensorType.INT64
        else -> ModelTensorType.UNSUPPORTED
    }
}
