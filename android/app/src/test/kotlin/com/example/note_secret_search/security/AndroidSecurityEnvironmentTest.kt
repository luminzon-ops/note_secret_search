package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

internal class AndroidSecurityEnvironmentTest {
    @Test
    fun `initialized legacy storage without password fails closed`() {
        val detector = SharedPreferencesLegacySecurityDetector(
            FakeLegacySecurityPreferenceStore(
                initialized = true,
                passwordPresent = false,
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            detector.hasLegacyPassword()
        }

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            error.code,
        )
    }

    @Test
    fun `blank stored legacy password fails closed`() {
        val detector = SharedPreferencesLegacySecurityDetector(
            FakeLegacySecurityPreferenceStore(
                initialized = false,
                passwordPresent = true,
                password = " ",
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            detector.readLegacyPassword()
        }

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            error.code,
        )
    }

    @Test
    fun `valid legacy password remains discoverable and clearable`() {
        val preferences = FakeLegacySecurityPreferenceStore(
            initialized = true,
            passwordPresent = true,
            password = "legacy-password",
        )
        val detector = SharedPreferencesLegacySecurityDetector(preferences)

        assertTrue(detector.hasLegacyPassword())
        assertEquals("legacy-password", detector.readLegacyPassword())
        assertTrue(detector.clearLegacyPassword())
        assertFalse(detector.hasLegacyPassword())
    }

    @Test
    fun `legacy preference cleanup failure uses a stable storage error`() {
        val detector = SharedPreferencesLegacySecurityDetector(
            FakeLegacySecurityPreferenceStore(
                initialized = true,
                passwordPresent = true,
                password = "legacy-password",
                clearFailure = IllegalStateException("preferences unavailable"),
            ),
        )

        val error = assertThrows(NativeSecurityException::class.java) {
            detector.clearLegacyPassword()
        }

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            error.code,
        )
    }
}

private class FakeLegacySecurityPreferenceStore(
    var initialized: Boolean,
    var passwordPresent: Boolean,
    var password: String? = null,
    var clearFailure: Throwable? = null,
) : LegacySecurityPreferenceStore {
    override fun contains(key: String): Boolean {
        return key == "database_password_material" && passwordPresent
    }

    override fun getBoolean(key: String, defaultValue: Boolean): Boolean {
        return if (key == "root_key_initialized") initialized else defaultValue
    }

    override fun getString(key: String): String? {
        return if (key == "database_password_material") password else null
    }

    override fun clear(): Boolean {
        clearFailure?.let { throw it }
        initialized = false
        passwordPresent = false
        password = null
        return true
    }
}
