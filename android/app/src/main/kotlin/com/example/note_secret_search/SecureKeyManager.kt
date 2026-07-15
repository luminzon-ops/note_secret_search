package com.example.note_secret_search

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import com.example.note_secret_search.security.AndroidKeystoreWrappingKeyBackend
import com.example.note_secret_search.security.AndroidSystemAuthCapabilities
import com.example.note_secret_search.security.AndroidWrappingKeyRepository
import com.example.note_secret_search.security.AtomicFileSecurityEnvelopeStore
import com.example.note_secret_search.security.NativeKeyringManager
import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityState
import com.example.note_secret_search.security.NativeUnlockMaterial
import com.example.note_secret_search.security.SharedPreferencesLegacySecurityDetector
import com.example.note_secret_search.security.SystemAuthenticator
import java.util.UUID

interface SecureKeyOperations {
    fun ensureRootKey()

    fun getDatabasePasswordMaterial(): String
}

internal interface SecureKeyPreferenceStore {
    fun isPersistenceAvailable(): Boolean

    fun isInitialized(): Boolean

    fun readDatabasePasswordMaterial(): String?

    fun persistInitializedMaterial(material: String): Boolean
}

private class SharedPreferencesSecureKeyPreferenceStore(
    private val preferences: SharedPreferences,
) : SecureKeyPreferenceStore {
    override fun isPersistenceAvailable(): Boolean {
        return !persistenceUnavailable
    }

    override fun isInitialized(): Boolean {
        return preferences.getBoolean(ROOT_KEY_INITIALIZED, false)
    }

    override fun readDatabasePasswordMaterial(): String? {
        return preferences.getString(DB_PASSWORD_KEY, null)
    }

    override fun persistInitializedMaterial(material: String): Boolean {
        if (persistenceUnavailable) {
            return false
        }

        return try {
            preferences.edit()
                .putString(DB_PASSWORD_KEY, material)
                .putBoolean(ROOT_KEY_INITIALIZED, true)
                .commit()
                .also { persisted ->
                    if (!persisted) {
                        persistenceUnavailable = true
                    }
                }
        } catch (error: Exception) {
            persistenceUnavailable = true
            throw error
        }
    }

    companion object {
        @Volatile
        private var persistenceUnavailable = false

        private const val ROOT_KEY_INITIALIZED = "root_key_initialized"
        private const val DB_PASSWORD_KEY = "database_password_material"
    }
}

class SecureKeyManager internal constructor(
    private val store: SecureKeyPreferenceStore,
) : SecureKeyOperations, NativeKeyringOperations {
    private var nativeKeyring: NativeKeyringOperations? = null

    constructor(context: Context) : this(
        SharedPreferencesSecureKeyPreferenceStore(
            context.getSharedPreferences("native_security", Context.MODE_PRIVATE),
        ),
    )

    constructor(
        context: Context,
        authenticator: SystemAuthenticator,
    ) : this(context) {
        val capabilities = AndroidSystemAuthCapabilities(context)
        nativeKeyring = NativeKeyringManager(
            apiLevel = Build.VERSION.SDK_INT,
            envelopeStore = AtomicFileSecurityEnvelopeStore(context),
            legacyDetector = SharedPreferencesLegacySecurityDetector(context),
            wrappingKeys = AndroidWrappingKeyRepository(
                apiLevel = Build.VERSION.SDK_INT,
                backend = AndroidKeystoreWrappingKeyBackend(),
            ),
            authenticator = authenticator,
            capabilities = capabilities::read,
        )
    }

    override fun ensureRootKey() {
        if (!store.isPersistenceAvailable()) {
            throw IllegalStateException("Database key material is unavailable.")
        }

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
        val persisted = try {
            store.persistInitializedMaterial(material)
        } catch (_: Exception) {
            throw IllegalStateException("Database key material could not be persisted.")
        }
        if (!persisted) {
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

    override fun getSecurityState(): NativeSecurityState {
        return requireNativeKeyring().getSecurityState()
    }

    override fun provisionWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        requireNativeKeyring().provisionWithSystemAuth(reason, result)
    }

    override fun unlockWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        requireNativeKeyring().unlockWithSystemAuth(reason, result)
    }

    override fun lock(): Any? {
        return requireNativeKeyring().lock()
    }

    private fun requireNativeKeyring(): NativeKeyringOperations {
        return checkNotNull(nativeKeyring) {
            "Native keyring dependencies were not configured."
        }
    }
}
