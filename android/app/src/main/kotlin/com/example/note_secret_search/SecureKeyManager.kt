package com.example.note_secret_search

import android.content.Context
import java.util.UUID

class SecureKeyManager(
    private val context: Context,
) {
    private val prefs = context.getSharedPreferences("native_security", Context.MODE_PRIVATE)

    fun ensureRootKey() {
        // MVP skeleton:
        // 1. Here we will generate/load a Keystore-backed root key.
        // 2. Prefer StrongBox when available.
        // 3. Later wrap DEK and PIN-derived fallback material here.
        prefs.edit()
            .putBoolean("root_key_initialized", true)
            .apply()

        if (!prefs.contains(DB_PASSWORD_KEY)) {
            prefs.edit()
                .putString(DB_PASSWORD_KEY, UUID.randomUUID().toString() + "-db-key")
                .apply()
        }
    }

    fun getDatabasePasswordMaterial(): String {
        ensureRootKey()
        return prefs.getString(DB_PASSWORD_KEY, "fallback-db-password-material")
            ?: "fallback-db-password-material"
    }

    companion object {
        private const val DB_PASSWORD_KEY = "database_password_material"
    }
}
