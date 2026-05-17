package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LocalLlmRuntimeTest {
    @Test
    fun `generation timeout budget is longer than model load timeout for real device first reply`() {
        assertEquals(30_000L, LLM_MODEL_LOAD_TIMEOUT_MS)
        assertEquals(45_000L, LLM_PREDICTION_TIMEOUT_MS)
        assertEquals(5_000L, LLM_PREDICTION_TIMEOUT_CLEANUP_MS)
        assertTrue(LLM_PREDICTION_TIMEOUT_MS > LLM_MODEL_LOAD_TIMEOUT_MS)
    }

    @Test
    fun `ensureModelReady returns ready after successful model load without probe generation`() {
        val tempModel = File.createTempFile("local-llm-ready", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        val state = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )

        assertTrue(state["ready"] as Boolean)
        assertEquals("ready", state["status"])
        assertEquals("本地 LLM runtime 已加载完成，可在首轮请求中执行真实生成。", state["reason"])
        assertEquals("gguf-fake", state["runtime"])
        assertTrue(backend.prompts.isEmpty())
        assertTrue(backend.maxTokens.isEmpty())
        assertEquals(1, backend.loadCalls)
    }

    @Test
    fun `generateText consumes first generation for caller prompt after load only readiness check`() {
        val tempModel = File.createTempFile("local-llm-generate-load-only", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = listOf(
                LocalLlmGenerateResult(
                    text = "这是首轮本地回答。",
                    finishReason = "stop",
                ),
            ),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        val result = runtime.generateText(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
            prompt = "帮我总结这段内容",
            usedPrivateContext = true,
        )

        assertEquals("这是首轮本地回答。", result["text"])
        assertEquals(listOf("帮我总结这段内容"), backend.prompts)
        assertEquals(listOf(96), backend.maxTokens)
        assertEquals(1, backend.loadCalls)
    }

    @Test
    fun `generateText returns generated text and preserves usedPrivateContext after load only readiness passes`() {
        val tempModel = File.createTempFile("local-llm-generate", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = listOf(
                LocalLlmGenerateResult(
                    text = "这是首轮本地回答。",
                    finishReason = "stop",
                ),
            ),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        val result = runtime.generateText(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
            prompt = "帮我总结这段内容",
            usedPrivateContext = true,
        )

        assertEquals("这是首轮本地回答。", result["text"])
        assertEquals("stop", result["finishReason"])
        assertTrue(result["usedPrivateContext"] as Boolean)
        assertEquals("ready", result["status"])
        assertEquals("gguf-fake", result["runtime"])
        assertEquals(listOf("帮我总结这段内容"), backend.prompts)
        assertEquals(listOf(96), backend.maxTokens)
        assertEquals(1, backend.loadCalls)
    }

    @Test
    fun `ensureModelReady reuses matching session even after generation lifecycle has started`() {
        val tempModel = File.createTempFile("local-llm-session-reuse", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        val first = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )
        assertEquals("ready", first["status"])
        assertEquals(1, backend.loadCalls)

        val activeSession = sessionManager.get("phi-local")
            ?: throw AssertionError("Expected a prepared session after ensureModelReady.")
        activeSession.hasEnteredGenerationLifecycle = true

        val second = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )
        assertEquals("ready", second["status"])
        assertEquals(
            "Matching session should be reused even after generation lifecycle started.",
            1,
            backend.loadCalls,
        )
        assertTrue(backend.releasedSessions.isEmpty())
    }

    @Test
    fun `generateText reuses prepared session on next top-level call after a completed generation`() {
        val tempModel = File.createTempFile("local-llm-session-reuse-generate", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = listOf(
                LocalLlmGenerateResult(text = "first generation result", finishReason = "stop"),
                LocalLlmGenerateResult(text = "second generation result", finishReason = "stop"),
            ),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        val first = runtime.generateText(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
            prompt = "first prompt",
            usedPrivateContext = false,
        )
        assertEquals("first generation result", first["text"])

        val second = runtime.generateText(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
            prompt = "second prompt",
            usedPrivateContext = false,
        )
        assertEquals("second generation result", second["text"])

        assertEquals(
            "Second top-level generation should reuse the prepared session instead of reloading the model.",
            1,
            backend.loadCalls,
        )
        assertTrue(backend.releasedSessions.isEmpty())
        assertEquals(listOf("first prompt", "second prompt"), backend.prompts)
    }

    @Test
    fun `generateText releases session when first caller generation fails after readiness load`() {
        val tempModel = File.createTempFile("local-llm-degraded", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
        )
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = LlmModelSessionManager(),
            backendFactory = FakeLlmBackendFactory(backend),
        )

        try {
            runtime.generateText(
                modelId = "phi-local",
                modelPath = tempModel.absolutePath,
                prompt = "你好",
                usedPrivateContext = false,
            )
        } catch (error: IllegalStateException) {
            assertEquals("No fake generate result configured.", error.message)
            assertFalse(backend.releasedSessions.isEmpty())
            return
        }

        throw AssertionError("Expected LocalLlmRuntime.generateText() to throw when generation fails.")
    }

    @Test
    fun `ensureModelReady degrades to unsupported when backend factory returns null for gguf file`() {
        // Regression test: when LlmBackendFactory.create() returns null for a .gguf file
        // (e.g., Huawei GGUF mitigation), ensureModelReady must return "unsupported" runtime.
        val tempModel = File.createTempFile("huawei-gguf-blocked", ".gguf").apply {
            deleteOnExit()
            writeText("fake gguf model")
        }
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = object : LlmBackendFactoryContract {
                // Simulates Huawei GGUF block: factory returns null for .gguf files
                override fun create(file: File): LocalLlmBackend? = null
            },
        )

        val state = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )

        assertEquals("degraded", state["status"])
        assertEquals("unsupported", state["runtime"])
        assertEquals(
            "当前模型格式暂无可用 Android 本地推理 backend。",
            state["reason"],
        )
        assertFalse(state["ready"] as Boolean)
    }

    @Test
    fun `ensureModelReady reloads session when same modelId is requested with a different modelPath`() {
        // Regression test: when ensureModelReady(modelId, pathA) succeeds then
        // ensureModelReady(modelId, pathB) is called, the runtime must release the
        // stale session and load the new model path — not reuse the pathA session.
        val tempModelA = File.createTempFile("model-a", ".gguf").apply {
            deleteOnExit()
            writeText("fake model A")
        }
        val tempModelB = File.createTempFile("model-b", ".gguf").apply {
            deleteOnExit()
            writeText("fake model B")
        }
        val backend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
        )
        val sessionManager = LlmModelSessionManager<LocalLlmBackendSession>()
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = sessionManager,
            backendFactory = FakeLlmBackendFactory(backend),
        )

        // First call: load model at pathA
        val stateA = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModelA.absolutePath,
        )
        assertTrue(stateA["ready"] as Boolean)
        assertEquals(tempModelA.absolutePath, stateA["modelPath"])
        assertEquals(1, backend.loadCalls)
        assertTrue(backend.releasedSessions.isEmpty())

        // Second call with same modelId but DIFFERENT pathB: must reload, not reuse
        val stateB = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModelB.absolutePath,
        )
        assertTrue(stateB["ready"] as Boolean)
        assertEquals(tempModelB.absolutePath, stateB["modelPath"])
        // Must have loaded a second time (fresh session for pathB)
        assertEquals(2, backend.loadCalls)
        // The pathA session must have been released before loading pathB.
        assertEquals(1, backend.releasedSessions.size)
        assertEquals(tempModelA.absolutePath, backend.releasedSessions[0].modelPath)
    }

    @Test
    fun `generateText releases reused session failure without immediate same-call retry`() {
        val tempModel = File.createTempFile("local-llm-retry", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val staleBackend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
            generateFailures = listOf(IllegalStateException("Timed out waiting for 120000 ms")),
        )
        val freshBackend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = listOf(
                LocalLlmGenerateResult(
                    text = "retry success",
                    finishReason = "stop",
                ),
            ),
        )
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = LlmModelSessionManager(),
            backendFactory = SequencedLlmBackendFactory(staleBackend, freshBackend),
        )

        val readyState = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )
        assertEquals("ready", readyState["status"])
        assertEquals(1, staleBackend.loadCalls)
        assertEquals(0, freshBackend.loadCalls)

        try {
            runtime.generateText(
                modelId = "phi-local",
                modelPath = tempModel.absolutePath,
                prompt = "你好",
                usedPrivateContext = false,
            )
        } catch (error: IllegalStateException) {
            assertEquals("Timed out waiting for 120000 ms", error.message)
            assertEquals(listOf("你好"), staleBackend.prompts)
            assertTrue(freshBackend.prompts.isEmpty())
            assertEquals(1, staleBackend.loadCalls)
            assertEquals(0, freshBackend.loadCalls)
            assertEquals(1, staleBackend.releasedSessions.size)
            return
        }

        throw AssertionError("Expected LocalLlmRuntime.generateText() to surface the reused-session failure.")
    }

    @Test
    fun `generateText recovers on next top-level call after reused session failure releases stale session`() {
        val tempModel = File.createTempFile("local-llm-recover-next-call", ".gguf").apply {
            deleteOnExit()
            writeText("fake model")
        }
        val staleBackend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = emptyList(),
            generateFailures = listOf(IllegalStateException("Timed out waiting for 120000 ms")),
        )
        val freshBackend = FakeLocalLlmBackend(
            inspectResult = LocalLlmInspectResult(
                supported = true,
                reason = "GGUF candidate",
            ),
            generated = listOf(
                LocalLlmGenerateResult(
                    text = "next call success",
                    finishReason = "stop",
                ),
            ),
        )
        val runtime = LocalLlmRuntime(
            packageName = "com.example.note_secret_search",
            sessionManager = LlmModelSessionManager(),
            backendFactory = SequencedLlmBackendFactory(staleBackend, freshBackend),
        )

        val readyState = runtime.ensureModelReady(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
        )
        assertEquals("ready", readyState["status"])
        assertEquals(1, staleBackend.loadCalls)
        assertEquals(0, freshBackend.loadCalls)

        try {
            runtime.generateText(
                modelId = "phi-local",
                modelPath = tempModel.absolutePath,
                prompt = "你好",
                usedPrivateContext = false,
            )
        } catch (error: IllegalStateException) {
            assertEquals("Timed out waiting for 120000 ms", error.message)
        }

        val result = runtime.generateText(
            modelId = "phi-local",
            modelPath = tempModel.absolutePath,
            prompt = "请继续",
            usedPrivateContext = false,
        )

        assertEquals("next call success", result["text"])
        assertEquals(listOf("你好"), staleBackend.prompts)
        assertEquals(listOf("请继续"), freshBackend.prompts)
        assertEquals(1, staleBackend.loadCalls)
        assertEquals(1, freshBackend.loadCalls)
        assertEquals(1, staleBackend.releasedSessions.size)
        assertTrue(freshBackend.releasedSessions.isEmpty())
    }
}

private class FakeLlmBackendFactory(
    private val backend: LocalLlmBackend?,
) : LlmBackendFactoryContract {
    override fun create(file: File): LocalLlmBackend? = backend
}

private class SequencedLlmBackendFactory(
    vararg backends: LocalLlmBackend,
) : LlmBackendFactoryContract {
    private val queue = ArrayDeque(backends.asList())

    override fun create(file: File): LocalLlmBackend? {
        return queue.removeFirstOrNull()
            ?: throw IllegalStateException("No fake backend configured for ${file.absolutePath}")
    }
}

private class FakeLocalLlmBackend(
    private val inspectResult: LocalLlmInspectResult,
    generated: List<LocalLlmGenerateResult>,
    generateFailures: List<Throwable> = emptyList(),
) : LocalLlmBackend {
    private val generatedQueue = ArrayDeque(generated)
    private val generateFailureQueue = ArrayDeque(generateFailures)

    val prompts = mutableListOf<String>()
    val maxTokens = mutableListOf<Int>()
    val configs = mutableListOf<LocalLlmGenerationConfig>()
    val releasedSessions = mutableListOf<LocalLlmBackendSession>()
    var loadCalls = 0

    override fun inspect(file: File): LocalLlmInspectResult = inspectResult

    override fun load(modelId: String, file: File): LocalLlmBackendSession {
        loadCalls++
        return LocalLlmBackendSession(
            modelId = modelId,
            modelPath = file.absolutePath,
            backendName = "gguf-fake",
            handle = loadCalls,
            backend = this,
        )
    }

    override fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ): LocalLlmGenerateResult {
        prompts += prompt
        this.maxTokens += maxTokens
        configs += config
        generateFailureQueue.removeFirstOrNull()?.let { throw it }
        return generatedQueue.removeFirstOrNull()
            ?: throw IllegalStateException("No fake generate result configured.")
    }

    override fun release(session: LocalLlmBackendSession) {
        releasedSessions += session
    }
}
