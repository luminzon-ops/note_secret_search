package com.example.note_secret_search

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Tests for Huawei/Honor GGUF backend blocking behavior.
 *
 * Huawei/Honor devices currently crash in the packaged rnllama GGUF native
 * completion path, so GGUF backend creation must be blocked on those vendors
 * until a proven-safe native path is available.
 */
class LlmBackendFactoryTest {

    @Test
    fun `shouldBlockGgufBackend returns true for HUAWEI manufacturer`() {
        assertTrue(shouldBlockGgufBackend("HUAWEI"))
    }

    @Test
    fun `shouldBlockGgufBackend returns true for Huawei manufacturer lowercase`() {
        assertTrue(shouldBlockGgufBackend("huawei"))
    }

    @Test
    fun `shouldBlockGgufBackend returns true for Huawei mixed case`() {
        assertTrue(shouldBlockGgufBackend("Huawei"))
    }

    @Test
    fun `shouldBlockGgufBackend returns true for HONOR manufacturer`() {
        assertTrue(shouldBlockGgufBackend("HONOR"))
    }

    @Test
    fun `shouldBlockGgufBackend returns true for Honor mixed case`() {
        assertTrue(shouldBlockGgufBackend("Honor"))
    }

    @Test
    fun `shouldBlockGgufBackend returns false for Samsung manufacturer`() {
        assertFalse(shouldBlockGgufBackend("Samsung"))
    }

    @Test
    fun `shouldBlockGgufBackend returns false for Google manufacturer`() {
        assertFalse(shouldBlockGgufBackend("Google"))
    }

    @Test
    fun `shouldBlockGgufBackend returns false for Xiaomi manufacturer`() {
        assertFalse(shouldBlockGgufBackend("Xiaomi"))
    }

    @Test
    fun `shouldBlockGgufBackend returns false for empty string`() {
        assertFalse(shouldBlockGgufBackend(""))
    }

    @Test
    fun `shouldBlockGgufBackend returns false for Huawei when Huawei-safe variant is bundled`() {
        assertFalse(
            shouldBlockGgufBackend(
                manufacturer = "Huawei",
                hasHuaweiSafeVariant = true,
            ),
        )
    }

    @Test
    fun `create returns null for gguf file on Huawei device`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "Huawei",
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.gguf"))

        assertTrue("GGUF backend must be blocked on Huawei devices", backend == null)
    }

    @Test
    fun `create returns null for gguf file on Honor device`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "Honor",
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.gguf"))

        assertTrue("GGUF backend must be blocked on Honor devices", backend == null)
    }

    @Test
    fun `create returns backend for gguf file on non-Huawei device`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "Samsung",
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.gguf"))

        assertTrue("GGUF backend must be created on non-Huawei devices", backend != null)
    }

    @Test
    fun `create returns null for non-gguf files regardless of device`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "Huawei",
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.onnx"))

        assertTrue("Non-GGUF files must return null regardless of device", backend == null)
    }

    @Test
    fun `create returns null for GGUF file on Huawei regardless of extension casing`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "HUAWEI",
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.GGUF"))

        assertTrue("GGUF backend must be blocked regardless of extension casing", backend == null)
    }

    @Test
    fun `create returns backend for gguf file on Huawei when Huawei-safe variant is bundled`() {
        val factory = LlmBackendFactoryDirect(
            manufacturer = "Huawei",
            hasHuaweiSafeVariant = true,
            createBackend = { FakeBackend() },
        )

        val backend = factory.create(File("/models/test.gguf"))

        assertTrue("GGUF backend must be created on Huawei when Huawei-safe variant is bundled", backend != null)
    }
}

/**
 * A minimal factory that tests the GGUF gating logic without requiring
 * a full Android Context. Takes manufacturer as a constructor parameter
 * so tests can control the device identity deterministically.
 */
private class LlmBackendFactoryDirect(
    private val manufacturer: String,
    private val hasHuaweiSafeVariant: Boolean = false,
    private val createBackend: (File) -> LocalLlmBackend?,
) : LlmBackendFactoryContract {
    override fun create(file: File): LocalLlmBackend? {
        val extension = file.extension.lowercase()
        return when (extension) {
            "gguf" -> {
                if (shouldBlockGgufBackend(manufacturer, hasHuaweiSafeVariant)) null else createBackend(file)
            }
            else -> null
        }
    }
}

private class FakeBackend : LocalLlmBackend {
    override fun inspect(file: File): LocalLlmInspectResult = LocalLlmInspectResult(supported = true, reason = "fake")
    override fun load(modelId: String, file: File): LocalLlmBackendSession = TODO()
    override fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ): LocalLlmGenerateResult = TODO()
    override fun release(session: LocalLlmBackendSession) {}
}
