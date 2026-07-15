package com.example.note_secret_search.security

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import androidx.biometric.BiometricManager

class SharedPreferencesLegacySecurityDetector(
    context: Context,
) : LegacySecurityDetector {
    private val preferences = context.getSharedPreferences(
        "native_security",
        Context.MODE_PRIVATE,
    )

    override fun hasLegacyPassword(): Boolean {
        return preferences.getBoolean("root_key_initialized", false) ||
            !preferences.getString("database_password_material", null).isNullOrBlank()
    }
}

interface LegacySecurityDetector {
    fun hasLegacyPassword(): Boolean
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
