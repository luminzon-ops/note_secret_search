package com.example.note_secret_search

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

interface SecureKeyOperations {
    fun ensureRootKey()

    fun getDatabasePasswordMaterial(): String
}

internal interface SecureKeyPreferenceStore {
    fun isInitialized(): Boolean

    fun readDatabasePasswordMaterial(): String?

    fun persistInitializedMaterial(material: String): Boolean
}

private class SharedPreferencesSecureKeyPreferenceStore(
    private val preferences: SharedPreferences,
) : SecureKeyPreferenceStore {
    override fun isInitialized(): Boolean {
        return preferences.getBoolean(ROOT_KEY_INITIALIZED, false)
    }

    override fun readDatabasePasswordMaterial(): String? {
        return preferences.getString(DB_PASSWORD_KEY, null)
    }

    override fun persistInitializedMaterial(material: String): Boolean {
        return preferences.edit()
            .putString(DB_PASSWORD_KEY, material)
            .putBoolean(ROOT_KEY_INITIALIZED, true)
            .commit()
    }

    companion object {
        private const val ROOT_KEY_INITIALIZED = "root_key_initialized"
        private const val DB_PASSWORD_KEY = "database_password_material"
    }
}

class SecureKeyManager internal constructor(
    private val store: SecureKeyPreferenceStore,
) : SecureKeyOperations {
    constructor(context: Context) : this(
        SharedPreferencesSecureKeyPreferenceStore(
            context.getSharedPreferences("native_security", Context.MODE_PRIVATE),
        ),
    )

    override fun ensureRootKey() {
        // MVP skeleton:
        // 1. Here we will generate/load a Keystore-backed root key.
        // 2. Prefer StrongBox when available.
        // 3. Later wrap DEK and PIN-derived fallback material here.
        val existingMaterial = store.readDatabasePasswordMaterial()
        if (store.isInitialized()) {
            if (existingMaterial.isNullOrBlank()) {
                throw IllegalStateException("Database key material is unavailable.")
            }
            return
        }

        val material = existingMaterial?.takeIf { it.isNotBlank() }
            ?: "${UUID.randomUUID()}-db-key"
        if (!store.persistInitializedMaterial(material)) {
            throw IllegalStateException("Database key material could not be persisted.")
        }
    }

    override fun getDatabasePasswordMaterial(): String {
        ensureRootKey()
        return store.readDatabasePasswordMaterial()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: throw IllegalStateException("Database key material is unavailable.")
    }
}
