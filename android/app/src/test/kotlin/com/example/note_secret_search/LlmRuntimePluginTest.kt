package com.example.note_secret_search

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class LlmRuntimePluginTest {
    @Test
    fun `inspectModel returns asynchronously without blocking method call thread`() {
        val workerStarted = CountDownLatch(1)
        val allowCompletion = CountDownLatch(1)
        val result = RecordingResult()
        val executor = Executors.newSingleThreadExecutor()
        val runtime = object : LocalLlmRuntimeContract {
            override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
                workerStarted.countDown()
                allowCompletion.await(2, TimeUnit.SECONDS)
                return mapOf(
                    "status" to "installed_unverified",
                    "ready" to false,
                    "runtime" to "candidate",
                )
            }

            override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("ensureModelReady should not be called in this test.")
            }

            override fun generateText(
                modelId: String,
                modelPath: String,
                prompt: String,
                usedPrivateContext: Boolean,
                config: LocalLlmGenerationConfig,
            ): Map<String, Any?> {
                throw UnsupportedOperationException("generateText should not be called in this test.")
            }

            override fun releaseModel(modelId: String) {
            }
        }

        try {
            val plugin = LlmRuntimePlugin(
                runtime = runtime,
                workerExecutor = executor,
                resultDispatcher = ImmediateResultDispatcher(),
            )

            val startedAt = System.nanoTime()
            plugin.onMethodCall(
                MethodCall(
                    "inspectModel",
                    mapOf(
                        "modelId" to "qwen2_5_0_5b_instruct_q4_k_m",
                        "modelPath" to "/data/user/0/com.example.note_secret_search/files/models/qwen.gguf",
                    ),
                ),
                result,
            )
            val elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

            assertTrue("onMethodCall should return quickly instead of blocking on inspectModel.", elapsedMillis < 100)
            assertTrue("worker should start model inspection asynchronously.", workerStarted.await(1, TimeUnit.SECONDS))
            assertNull("result should not be completed before worker finishes.", result.successValue)

            allowCompletion.countDown()

            assertTrue("result.success should be invoked after worker completion.", result.successLatch.await(1, TimeUnit.SECONDS))
            val payload = result.successValue as Map<*, *>
            assertEquals("installed_unverified", payload["status"])
            assertEquals(false, payload["ready"])
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `ensureModelReady returns asynchronously without blocking method call thread`() {
        val workerStarted = CountDownLatch(1)
        val allowCompletion = CountDownLatch(1)
        val result = RecordingResult()
        val executor = Executors.newSingleThreadExecutor()
        val runtime = object : LocalLlmRuntimeContract {
            override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("inspectModel should not be called in this test.")
            }

            override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
                workerStarted.countDown()
                allowCompletion.await(2, TimeUnit.SECONDS)
                return mapOf(
                    "status" to "ready",
                    "ready" to true,
                    "runtime" to "gguf-llama-cpp",
                )
            }

            override fun generateText(
                modelId: String,
                modelPath: String,
                prompt: String,
                usedPrivateContext: Boolean,
                config: LocalLlmGenerationConfig,
            ): Map<String, Any?> {
                throw UnsupportedOperationException("generateText should not be called in this test.")
            }

            override fun releaseModel(modelId: String) {
            }
        }

        try {
            val plugin = LlmRuntimePlugin(
                runtime = runtime,
                workerExecutor = executor,
                resultDispatcher = ImmediateResultDispatcher(),
            )

            val startedAt = System.nanoTime()
            plugin.onMethodCall(
                MethodCall(
                    "ensureModelReady",
                    mapOf(
                        "modelId" to "qwen2_5_0_5b_instruct_q4_k_m",
                        "modelPath" to "/data/user/0/com.example.note_secret_search/files/models/qwen.gguf",
                    ),
                ),
                result,
            )
            val elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

            assertTrue("onMethodCall should return quickly instead of blocking on runtime work.", elapsedMillis < 100)
            assertTrue("worker should start runtime validation asynchronously.", workerStarted.await(1, TimeUnit.SECONDS))
            assertNull("result should not be completed before worker finishes.", result.successValue)

            allowCompletion.countDown()

            assertTrue("result.success should be invoked after worker completion.", result.successLatch.await(1, TimeUnit.SECONDS))
            val payload = result.successValue as Map<*, *>
            assertEquals("ready", payload["status"])
            assertEquals(true, payload["ready"])
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `generateText reports runtime errors from worker thread`() {
        val result = RecordingResult()
        val executor = Executors.newSingleThreadExecutor()
        val runtime = object : LocalLlmRuntimeContract {
            override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("inspectModel should not be called in this test.")
            }

            override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("ensureModelReady should not be called in this test.")
            }

            override fun generateText(
                modelId: String,
                modelPath: String,
                prompt: String,
                usedPrivateContext: Boolean,
                config: LocalLlmGenerationConfig,
            ): Map<String, Any?> {
                throw IllegalStateException("runtime degraded")
            }

            override fun releaseModel(modelId: String) {
            }
        }

        try {
            val plugin = LlmRuntimePlugin(
                runtime = runtime,
                workerExecutor = executor,
                resultDispatcher = ImmediateResultDispatcher(),
            )

            plugin.onMethodCall(
                MethodCall(
                    "generateText",
                    mapOf(
                        "modelId" to "qwen2_5_0_5b_instruct_q4_k_m",
                        "modelPath" to "/data/user/0/com.example.note_secret_search/files/models/qwen.gguf",
                        "prompt" to "你好",
                        "usedPrivateContext" to true,
                    ),
                ),
                result,
            )

            assertTrue("result.error should be invoked from async worker failures.", result.errorLatch.await(1, TimeUnit.SECONDS))
            assertEquals("RUNTIME_NOT_READY", result.errorCode)
            assertEquals("runtime degraded", result.errorMessage)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `generateText forwards conservative generation config from method call`() {
        val result = RecordingResult()
        val executor = Executors.newSingleThreadExecutor()
        var capturedConfig: LocalLlmGenerationConfig? = null
        val runtime = object : LocalLlmRuntimeContract {
            override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("inspectModel should not be called in this test.")
            }

            override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("ensureModelReady should not be called in this test.")
            }

            override fun generateText(
                modelId: String,
                modelPath: String,
                prompt: String,
                usedPrivateContext: Boolean,
                config: LocalLlmGenerationConfig,
            ): Map<String, Any?> {
                capturedConfig = config
                return mapOf(
                    "status" to "ready",
                    "text" to "stable",
                    "finishReason" to "stop",
                )
            }

            override fun releaseModel(modelId: String) {
            }
        }

        try {
            val plugin = LlmRuntimePlugin(
                runtime = runtime,
                workerExecutor = executor,
                resultDispatcher = ImmediateResultDispatcher(),
            )

            plugin.onMethodCall(
                MethodCall(
                    "generateText",
                    mapOf(
                        "modelId" to "smollm2_360m_instruct_q4_k_m",
                        "modelPath" to "/data/user/0/com.example.note_secret_search/files/models/smollm.gguf",
                        "prompt" to "你好",
                        "usedPrivateContext" to true,
                        "maxOutputTokens" to 96,
                        "maxPromptChars" to 1200,
                        "contextLength" to 1024,
                        "conservativeMode" to true,
                    ),
                ),
                result,
            )

            assertTrue("result.success should be invoked after generation.", result.successLatch.await(1, TimeUnit.SECONDS))
            val config = capturedConfig ?: throw AssertionError("Expected generateText to receive config.")
            assertEquals(96, config.maxOutputTokens)
            assertEquals(1200, config.maxPromptChars)
            assertEquals(1024, config.contextLength)
            assertEquals(true, config.conservativeMode)
            assertEquals(false, config.emitPartialCompletion)
            assertEquals(0.7, config.temperature, 0.0)
            assertEquals(40, config.topK)
            assertEquals(0.9, config.topP, 0.0)
            assertEquals(42, config.seed)
            assertEquals(listOf("</s>", "<|im_end|>", "<|endoftext|>"), config.stopSequences)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `generateMultimodalText forwards model projector image and reasoning flag`() {
        val result = RecordingResult()
        val executor = Executors.newSingleThreadExecutor()
        var capturedModelPath: String? = null
        var capturedMmprojPath: String? = null
        var capturedImagePath: String? = null
        var capturedReasoningEnabled: Boolean? = null
        val multimodalRuntime = object : MultimodalLlmRuntimeContract {
            override fun ensureModelReady(modelId: String, modelPath: String, mmprojPath: String): Map<String, Any?> {
                throw UnsupportedOperationException("ensureModelReady should not be called in this test.")
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
                capturedModelPath = modelPath
                capturedMmprojPath = mmprojPath
                capturedImagePath = imagePath
                capturedReasoningEnabled = reasoningEnabled
                return mapOf(
                    "status" to "ready",
                    "ready" to true,
                    "text" to "A cat",
                )
            }
        }

        try {
            val plugin = LlmRuntimePlugin(
                runtime = throwingTextRuntime(),
                multimodalRuntime = multimodalRuntime,
                workerExecutor = executor,
                resultDispatcher = ImmediateResultDispatcher(),
            )

            plugin.onMethodCall(
                MethodCall(
                    "generateMultimodalText",
                    mapOf(
                        "modelId" to "minicpm_v_4_6_q4_k_m",
                        "modelPath" to "/models/model.gguf",
                        "mmprojPath" to "/models/mmproj-model-f16.gguf",
                        "imagePath" to "/cache/input.jpg",
                        "prompt" to "Describe it",
                        "reasoningEnabled" to false,
                    ),
                ),
                result,
            )

            assertTrue("result.success should be invoked after multimodal generation.", result.successLatch.await(1, TimeUnit.SECONDS))
            assertEquals("/models/model.gguf", capturedModelPath)
            assertEquals("/models/mmproj-model-f16.gguf", capturedMmprojPath)
            assertEquals("/cache/input.jpg", capturedImagePath)
            assertEquals(false, capturedReasoningEnabled)
        } finally {
            executor.shutdownNow()
        }
    }
}

private fun throwingTextRuntime(): LocalLlmRuntimeContract {
    return object : LocalLlmRuntimeContract {
        override fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
            throw UnsupportedOperationException("text runtime should not be called in this test.")
        }

        override fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
            throw UnsupportedOperationException("text runtime should not be called in this test.")
        }

        override fun generateText(
            modelId: String,
            modelPath: String,
            prompt: String,
            usedPrivateContext: Boolean,
            config: LocalLlmGenerationConfig,
        ): Map<String, Any?> {
            throw UnsupportedOperationException("text runtime should not be called in this test.")
        }

        override fun releaseModel(modelId: String) {
        }
    }
}

private class ImmediateResultDispatcher : ResultDispatcher {
    override fun dispatch(block: () -> Unit) {
        block()
    }
}

private class RecordingResult : MethodChannel.Result {
    val successLatch = CountDownLatch(1)
    val errorLatch = CountDownLatch(1)

    @Volatile
    var successValue: Any? = null

    @Volatile
    var errorCode: String? = null

    @Volatile
    var errorMessage: String? = null

    override fun success(result: Any?) {
        successValue = result
        successLatch.countDown()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        errorLatch.countDown()
    }

    override fun notImplemented() {
        errorCode = "NOT_IMPLEMENTED"
        errorLatch.countDown()
    }
}
