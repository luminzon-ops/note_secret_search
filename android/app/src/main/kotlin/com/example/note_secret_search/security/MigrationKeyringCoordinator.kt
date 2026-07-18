package com.example.note_secret_search.security

internal class MigrationKeyringCoordinator(
    private val envelopeStore: SecurityEnvelopeStore,
    private val legacyStore: LegacySecurityDetector,
    private val provisioner: KeyringProvisioner,
    private val unlocker: KeyringUnlocker,
    private val capabilities: () -> SystemAuthCapabilities,
    private val completionVerifier: MigrationCompletionVerifier,
    private val migrationFiles: MigrationFileCoordinator?,
) {
    fun begin(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        if (!legacyStore.hasLegacyPasswordSafely()) {
            result.error(NativeSecurityException(NativeSecurityErrorCode.MIGRATION_REQUIRED))
            return
        }
        val legacyPassword = try {
            legacyStore.readLegacyPassword()
                ?.takeIf { it.isNotBlank() }
                ?: throw NativeSecurityException(
                    NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                )
        } catch (error: NativeSecurityException) {
            result.error(error)
            return
        } catch (error: Throwable) {
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                    error,
                ),
            )
            return
        }
        migrationFiles?.detect()
        val migrationResult = migrationResult(result, legacyPassword)
        val keyset = envelopeStore.readRecoverableKeyset()
        if (keyset == null) {
            val auth = capabilities()
            if (!auth.deviceCredentialAvailable) {
                result.error(
                    NativeSecurityException(
                        NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
                    ),
                )
                return
            }
            provisioner.provision(reason, auth, migrationResult)
            return
        }
        unlocker.unlock(reason, keyset, capabilities(), migrationResult)
    }

    fun commit(
        keyId: String,
        activeDigest: String,
        result: NativeResult<Unit>,
    ) {
        val keyset = envelopeStore.readRecoverableKeyset()
        if (keyset == null) {
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
                ),
            )
            return
        }
        if (
            keyset.keyId != keyId ||
            !completionVerifier.isCleanupComplete(keyId, activeDigest)
        ) {
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.RECOVERY_REQUIRED,
                ),
            )
            return
        }
        if (
            legacyStore.hasLegacyPasswordSafely() &&
            !legacyStore.clearLegacyPassword()
        ) {
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                ),
            )
            return
        }
        result.success(Unit)
    }

    fun finish(keyId: String) {
        if (legacyStore.hasLegacyPasswordSafely()) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_REQUIRED,
            )
        }
        val keyset = try {
            envelopeStore.readRecoverableKeyset()
        } catch (_: NativeSecurityException) {
            null
        }
        if (keyset?.keyId != keyId) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.RECOVERY_REQUIRED,
            )
        }
        migrationFiles.requireConfigured().finish(keyId)
    }

    private fun migrationResult(
        result: NativeResult<NativeUnlockMaterial>,
        legacyPassword: String,
    ): NativeResult<NativeUnlockMaterial> {
        val operationResult = result as? OperationAwareResult
        return object : NativeResult<NativeUnlockMaterial>, OperationAwareResult {
            override val operationId: Long = operationResult?.operationId ?: 0L

            override fun isActiveOperation(): Boolean {
                return operationResult?.isActiveOperation() ?: true
            }

            override fun registerCancellationCleanup(cleanup: () -> Unit): Boolean {
                return operationResult?.registerCancellationCleanup(cleanup) ?: true
            }

            override fun runIfActive(operation: () -> Unit): Boolean {
                return operationResult?.runIfActive(operation) ?: run {
                    operation()
                    true
                }
            }

            override fun success(value: NativeUnlockMaterial) {
                try {
                    migrationFiles?.markKeyringReady(value.keyId)
                    result.success(
                        NativeUnlockMaterial(
                            keyId = value.keyId,
                            databaseKey = value.databaseKey.clone(),
                            fieldKey = value.fieldKey.clone(),
                            unlockMethod = value.unlockMethod,
                            legacyDatabasePassword = legacyPassword.toByteArray(
                                Charsets.UTF_8,
                            ),
                        ),
                    )
                } catch (error: NativeSecurityException) {
                    result.error(error)
                } catch (error: Throwable) {
                    result.error(
                        NativeSecurityException(
                            NativeSecurityErrorCode.MIGRATION_FAILED,
                            error,
                        ),
                    )
                } finally {
                    value.zeroize()
                }
            }

            override fun error(error: NativeSecurityException) {
                result.error(error)
            }
        }
    }
}

fun interface MigrationCompletionVerifier {
    fun isCleanupComplete(keyId: String, activeDigest: String): Boolean
}
