package com.example.note_secret_search.security

import android.app.KeyguardManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.biometric.BiometricManager

class SharedPreferencesLegacySecurityDetector internal constructor(
    private val preferences: LegacySecurityPreferenceStore,
) : LegacySecurityDetector {
    constructor(context: Context) : this(
        AndroidLegacySecurityPreferenceStore(
            context.getSharedPreferences(
                "native_security",
                Context.MODE_PRIVATE,
            ),
        ),
    )

    override fun hasLegacyPassword(): Boolean {
        return readStoredPassword() != null
    }

    override fun readLegacyPassword(): String? {
        return readStoredPassword()
    }

    override fun clearLegacyPassword(): Boolean {
        return try {
            preferences.clear()
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Throwable) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                error,
            )
        }
    }

    private fun readStoredPassword(): String? {
        val initialized = preferences.getBoolean("root_key_initialized", false)
        val materialPresent = preferences.contains("database_password_material")
        val material = preferences.getString("database_password_material")
        if (
            (initialized && !materialPresent) ||
            (materialPresent && material.isNullOrBlank())
        ) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            )
        }
        return material?.takeIf { it.isNotBlank() }
    }
}

internal interface LegacySecurityPreferenceStore {
    fun contains(key: String): Boolean

    fun getBoolean(key: String, defaultValue: Boolean): Boolean

    fun getString(key: String): String?

    fun clear(): Boolean
}

private class AndroidLegacySecurityPreferenceStore(
    private val preferences: SharedPreferences,
) : LegacySecurityPreferenceStore {
    override fun contains(key: String): Boolean = preferences.contains(key)

    override fun getBoolean(key: String, defaultValue: Boolean): Boolean =
        preferences.getBoolean(key, defaultValue)

    override fun getString(key: String): String? =
        preferences.getString(key, null)

    override fun clear(): Boolean {
        return preferences.edit()
            .remove("root_key_initialized")
            .remove("database_password_material")
            .commit()
    }
}

interface LegacySecurityDetector {
    fun hasLegacyPassword(): Boolean

    fun readLegacyPassword(): String?

    fun clearLegacyPassword(): Boolean
}

internal fun LegacySecurityDetector.hasLegacyPasswordSafely(): Boolean {
    return try {
        hasLegacyPassword()
    } catch (error: NativeSecurityException) {
        throw error
    } catch (error: Throwable) {
        throw NativeSecurityException(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            error,
        )
    }
}

class AndroidSystemAuthCapabilities(
    private val context: Context,
) {
    fun read(): SystemAuthCapabilities {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        val deviceCredentialAvailable = keyguard?.isDeviceSecure == true
        val strongBiometricAvailable = BiometricManager.from(context).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG,
        ) == BiometricManager.BIOMETRIC_SUCCESS
        return SystemAuthCapabilities(
            deviceCredentialAvailable = deviceCredentialAvailable,
            strongBiometricAvailable = strongBiometricAvailable,
        )
    }
}
