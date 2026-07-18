package com.example.note_secret_search

import android.content.Context
import android.os.Build
import com.example.note_secret_search.security.AndroidKeystoreWrappingKeyBackend
import com.example.note_secret_search.security.AndroidPinThrottleClock
import com.example.note_secret_search.security.AndroidSystemAuthCapabilities
import com.example.note_secret_search.security.AndroidWrappingKeyRepository
import com.example.note_secret_search.security.AndroidMigrationFileSetAccess
import com.example.note_secret_search.security.AtomicFileMigrationJournalStore
import com.example.note_secret_search.security.AtomicFileSecurityEnvelopeStore
import com.example.note_secret_search.security.MigrationFileCoordinator
import com.example.note_secret_search.security.NativeKeyringManager
import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityState
import com.example.note_secret_search.security.NativeUnlockMaterial
import com.example.note_secret_search.security.PersistentPinAttemptThrottle
import com.example.note_secret_search.security.SharedPreferencesPinThrottleStore
import com.example.note_secret_search.security.SharedPreferencesLegacySecurityDetector
import com.example.note_secret_search.security.SystemAuthenticator

class SecureKeyManager(
    context: Context,
    authenticator: SystemAuthenticator,
) : NativeKeyringOperations {
    private var nativeKeyring: NativeKeyringOperations? = run {
        val capabilities = AndroidSystemAuthCapabilities(context)
        val migrationFiles = MigrationFileCoordinator(
            files = AndroidMigrationFileSetAccess(context),
            journalStore = AtomicFileMigrationJournalStore(context),
        )
        NativeKeyringManager(
            apiLevel = Build.VERSION.SDK_INT,
            envelopeStore = AtomicFileSecurityEnvelopeStore(context),
            legacyDetector = SharedPreferencesLegacySecurityDetector(context),
            wrappingKeys = AndroidWrappingKeyRepository(
                apiLevel = Build.VERSION.SDK_INT,
                backend = AndroidKeystoreWrappingKeyBackend(),
            ),
            authenticator = authenticator,
            capabilities = capabilities::read,
            pinThrottle = PersistentPinAttemptThrottle(
                store = SharedPreferencesPinThrottleStore(context),
                clock = AndroidPinThrottleClock(context),
            ),
            migrationFileCoordinator = migrationFiles,
        )
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

    override fun configurePin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        requireNativeKeyring().configurePin(reason, pin, result)
    }

    override fun unlockWithPin(
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        requireNativeKeyring().unlockWithPin(pin, result)
    }

    override fun rebindSystemAuthWithPin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        requireNativeKeyring().rebindSystemAuthWithPin(reason, pin, result)
    }

    override fun removePin(
        reason: String,
        result: NativeResult<Unit>,
    ) {
        requireNativeKeyring().removePin(reason, result)
    }

    override fun beginLegacyMigration(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        requireNativeKeyring().beginLegacyMigration(reason, result)
    }

    override fun getLegacyMigrationState(): Map<String, Any?> {
        return requireNativeKeyring().getLegacyMigrationState()
    }

    override fun prepareLegacyMigrationBackup(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().prepareLegacyMigrationBackup(keyId)
    }

    override fun prepareLegacyMigrationPending(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().prepareLegacyMigrationPending(keyId)
    }

    override fun markLegacyMigrationRowsCopied(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().markLegacyMigrationRowsCopied(keyId)
    }

    override fun markLegacyMigrationValidated(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().markLegacyMigrationValidated(keyId)
    }

    override fun activateLegacyMigration(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().activateLegacyMigration(keyId)
    }

    override fun markLegacyMigrationPostSwapValidated(
        keyId: String,
    ): Map<String, Any?> {
        return requireNativeKeyring().markLegacyMigrationPostSwapValidated(keyId)
    }

    override fun cleanupLegacyMigrationFiles(keyId: String): Map<String, Any?> {
        return requireNativeKeyring().cleanupLegacyMigrationFiles(keyId)
    }

    override fun finishLegacyMigration(keyId: String) {
        requireNativeKeyring().finishLegacyMigration(keyId)
    }

    override fun commitLegacyMigration(
        keyId: String,
        activeDigest: String,
        result: NativeResult<Unit>,
    ) {
        requireNativeKeyring().commitLegacyMigration(
            keyId,
            activeDigest,
            result,
        )
    }

    override fun abortLegacyMigration(result: NativeResult<Unit>) {
        requireNativeKeyring().abortLegacyMigration(result)
    }

    override fun lock(): Any? {
        return requireNativeKeyring().lock()
    }

    fun close() {
        val keyring = nativeKeyring
        nativeKeyring = null
        if (keyring is AutoCloseable) {
            keyring.close()
        } else {
            keyring?.lock()
        }
    }

    private fun requireNativeKeyring(): NativeKeyringOperations {
        return checkNotNull(nativeKeyring) {
            "Native keyring dependencies were not configured."
        }
    }
}
