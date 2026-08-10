package com.example.note_secret_search.security

interface NativeKeyringOperations {
    fun getSecurityState(): NativeSecurityState

    fun provisionWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    )

    fun unlockWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    )

    fun configurePin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    )

    fun unlockWithPin(
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    )

    fun rebindSystemAuthWithPin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    )

    fun removePin(
        reason: String,
        result: NativeResult<Unit>,
    )

    fun beginLegacyMigration(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    )

    fun getLegacyMigrationState(): Map<String, Any?>

    fun prepareLegacyMigrationBackup(keyId: String): Map<String, Any?>

    fun prepareLegacyMigrationPending(keyId: String): Map<String, Any?>

    fun markLegacyMigrationRowsCopied(keyId: String): Map<String, Any?>

    fun markLegacyMigrationValidated(keyId: String): Map<String, Any?>

    fun activateLegacyMigration(keyId: String): Map<String, Any?>

    fun markLegacyMigrationPostSwapValidated(keyId: String): Map<String, Any?>

    fun cleanupLegacyMigrationFiles(keyId: String): Map<String, Any?>

    fun finishLegacyMigration(keyId: String)

    fun commitLegacyMigration(
        keyId: String,
        activeDigest: String,
        result: NativeResult<Unit>,
    )

    fun abortLegacyMigration(result: NativeResult<Unit>)

    fun lock(): Any?
}
