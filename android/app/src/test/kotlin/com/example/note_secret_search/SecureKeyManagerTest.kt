package com.example.note_secret_search

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SecureKeyManagerTest {
    @Test
    fun `fresh store persists random database material and initialization marker`() {
        val store = FakeSecureKeyPreferenceStore()
        val manager = SecureKeyManager(store)

        manager.ensureRootKey()
        val material = manager.getDatabasePasswordMaterial()

        assertTrue(material.isNotBlank())
        assertNotEquals("fallback-db-password-material", material)
        assertTrue(store.initialized)
        assertEquals(material, store.material)
    }

    @Test
    fun `existing valid database material is preserved`() {
        val store = FakeSecureKeyPreferenceStore(
            initialized = true,
            material = "existing-material",
        )
        val manager = SecureKeyManager(store)

        manager.ensureRootKey()

        assertEquals("existing-material", manager.getDatabasePasswordMaterial())
        assertEquals(0, store.persistCalls)
    }

    @Test(expected = IllegalStateException::class)
    fun `initialized store with missing database material fails closed`() {
        val manager = SecureKeyManager(
            FakeSecureKeyPreferenceStore(initialized = true),
        )

        manager.ensureRootKey()
    }

    @Test(expected = IllegalStateException::class)
    fun `initialized store with blank database material fails closed`() {
        val manager = SecureKeyManager(
            FakeSecureKeyPreferenceStore(
                initialized = true,
                material = "   ",
            ),
        )

        manager.getDatabasePasswordMaterial()
    }

    @Test(expected = IllegalStateException::class)
    fun `failed fresh material persistence fails closed`() {
        val store = FakeSecureKeyPreferenceStore(persistResult = false)
        val manager = SecureKeyManager(store)

        manager.ensureRootKey()
    }

    @Test
    fun `native handler maps key failures without exposing exception details`() {
        val operations = object : SecureKeyOperations {
            override fun ensureRootKey() {
                throw IllegalStateException("sensitive storage detail")
            }

            override fun getDatabasePasswordMaterial(): String {
                throw IllegalStateException("sensitive key detail")
            }
        }
        val result = RecordingSecureKeyResult()
        val handler = SecureKeyMethodHandler(operations)

        handler.ensureRootKey(result)

        assertEquals("SECURE_KEY_UNAVAILABLE", result.errorCode)
        assertEquals("Secure key material is unavailable.", result.errorMessage)
        assertFalse(result.errorMessage!!.contains("sensitive"))
    }
}

private class FakeSecureKeyPreferenceStore(
    var initialized: Boolean = false,
    var material: String? = null,
    private val persistResult: Boolean = true,
) : SecureKeyPreferenceStore {
    var persistCalls = 0

    override fun isInitialized(): Boolean = initialized

    override fun readDatabasePasswordMaterial(): String? = material

    override fun persistInitializedMaterial(material: String): Boolean {
        persistCalls += 1
        if (!persistResult) {
            return false
        }
        this.material = material
        initialized = true
        return true
    }
}

private class RecordingSecureKeyResult : MethodChannel.Result {
    var errorCode: String? = null
    var errorMessage: String? = null

    override fun success(result: Any?) {
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
        this.errorMessage = errorMessage
    }

    override fun notImplemented() {
    }
}
