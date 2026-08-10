package com.example.note_secret_search.security

internal class NativeSecurityStateResolver(
    private val apiLevel: Int,
    private val envelopeStore: SecurityEnvelopeStore,
    private val legacyDetector: LegacySecurityDetector,
    private val wrappingKeys: WrappingKeyRepository,
    private val capabilities: () -> SystemAuthCapabilities,
    private val migrationFileCoordinator: MigrationFileCoordinator?,
) {
    fun resolve(): NativeSecurityState {
        val auth = capabilities()
        val migrationJournal = try {
            migrationFileCoordinator?.currentJournal()
        } catch (_: NativeSecurityException) {
            return state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
        val activeDatabasePresent = try {
            migrationFileCoordinator?.hasActiveDatabase() == true
        } catch (_: Throwable) {
            return state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
        val legacyPasswordPresent = try {
            legacyDetector.hasLegacyPasswordSafely()
        } catch (_: NativeSecurityException) {
            return state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
        val migrationRequired =
            legacyPasswordPresent || migrationJournal != null
        val encoded = try {
            envelopeStore.read()
        } catch (_: Throwable) {
            return state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
            ?: return state(
                status = when {
                    migrationJournal != null &&
                        migrationJournal.stage >=
                        MigrationJournalStage.KEYRING_READY ->
                        SecurityStatus.RECOVERY_REQUIRED
                    migrationJournal != null && !legacyPasswordPresent ->
                        SecurityStatus.RECOVERY_REQUIRED
                    activeDatabasePresent && !legacyPasswordPresent ->
                        SecurityStatus.RECOVERY_REQUIRED
                    migrationRequired ->
                        SecurityStatus.LEGACY_MIGRATION_REQUIRED
                    else -> SecurityStatus.UNPROVISIONED
                },
                auth = auth,
            )
        val keyset = try {
            SecurityKeysetCodec.decodeRecoverable(encoded)
        } catch (_: NativeSecurityException) {
            return state(
                SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
        if (
            migrationJournal != null &&
            migrationJournal.stage >= MigrationJournalStage.KEYRING_READY &&
            migrationJournal.keyId != keyset.keyId
        ) {
            return state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        }
        val envelope = requiredStateEnvelope(keyset)
            ?: return withMigrationStatus(
                stateWithoutSystemEnvelope(keyset, auth),
                migrationRequired,
                migrationJournal,
                legacyPasswordPresent,
            )
        val handle = try {
            wrappingKeys.load(envelope.keyAlias)
        } catch (_: WrappingKeyInvalidatedException) {
            null
        } catch (error: KeystoreOperationFailure) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE,
                error,
            )
        }
        val usableHandle = handle?.let {
            probeEnvelope(it, envelope)
        }
        val resolvedSecurityLevel = usableHandle?.let {
            resolveSecurityLevel(
                stored = envelope.securityLevel,
                loaded = it.securityLevel,
            )
        }
        val resolvedState = if (resolvedSecurityLevel != null) {
            state(
                status = SecurityStatus.LOCKED,
                keyId = keyset.keyId,
                pinConfigured = keyset.pinEnvelope != null,
                securityLevel = resolvedSecurityLevel,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        } else if (keyset.pinEnvelope != null) {
            state(
                status = SecurityStatus.LOCKED,
                keyId = keyset.keyId,
                pinConfigured = true,
                systemRebindRequired = true,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        } else {
            state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        }
        return withMigrationStatus(
            resolvedState,
            migrationRequired,
            migrationJournal,
            legacyPasswordPresent,
        )
    }

    private fun probeEnvelope(
        handle: WrappingKeyHandle,
        envelope: SecurityEnvelope,
    ): WrappingKeyHandle? {
        return try {
            handle.decryptionCipher(envelope.nonce)
            handle
        } catch (_: WrappingKeyInvalidatedException) {
            null
        } catch (_: WrappingKeyAuthenticationRequiredException) {
            handle
        } catch (error: KeystoreOperationFailure) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE,
                error,
            )
        }
    }

    private fun resolveSecurityLevel(
        stored: KeySecurityLevel,
        loaded: KeySecurityLevel,
    ): KeySecurityLevel? {
        if (stored == loaded) {
            return loaded
        }
        if (
            apiLevel in 28..30 &&
            stored == KeySecurityLevel.STRONG_BOX &&
            loaded == KeySecurityLevel.TEE
        ) {
            return KeySecurityLevel.UNKNOWN
        }
        return null
    }

    private fun requiredStateEnvelope(
        keyset: SecurityKeyset,
    ): SecurityEnvelope? {
        return keyset.envelopes.firstOrNull {
            it.kind == EnvelopeKind.COMBINED
        } ?: keyset.envelopes.firstOrNull {
            it.kind == EnvelopeKind.DEVICE_CREDENTIAL
        }
    }

    private fun stateWithoutSystemEnvelope(
        keyset: SecurityKeyset,
        auth: SystemAuthCapabilities,
    ): NativeSecurityState {
        return if (keyset.pinEnvelope != null) {
            state(
                status = SecurityStatus.LOCKED,
                keyId = keyset.keyId,
                pinConfigured = true,
                systemRebindRequired = true,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        } else {
            state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
                pinResetRequired = keyset.pinResetRequired,
                auth = auth,
            )
        }
    }

    private fun state(
        status: SecurityStatus,
        keyId: String? = null,
        pinConfigured: Boolean = false,
        securityLevel: KeySecurityLevel = KeySecurityLevel.UNKNOWN,
        systemRebindRequired: Boolean = false,
        pinResetRequired: Boolean = false,
        auth: SystemAuthCapabilities,
    ): NativeSecurityState {
        return NativeSecurityState(
            status = status,
            keyId = keyId,
            pinConfigured = pinConfigured,
            deviceCredentialAvailable = auth.deviceCredentialAvailable,
            strongBiometricAvailable = auth.strongBiometricAvailable,
            securityLevel = securityLevel,
            systemRebindRequired = systemRebindRequired,
            pinResetRequired = pinResetRequired,
        )
    }

    private fun withMigrationStatus(
        resolved: NativeSecurityState,
        migrationRequired: Boolean,
        migrationJournal: MigrationJournal?,
        legacyPasswordPresent: Boolean,
    ): NativeSecurityState {
        if (!migrationRequired ||
            resolved.status == SecurityStatus.RECOVERY_REQUIRED
        ) {
            return resolved
        }
        if (
            migrationJournal != null &&
            migrationJournal.stage !=
            MigrationJournalStage.CLEANUP_COMPLETE &&
            !legacyPasswordPresent
        ) {
            return resolved.copy(status = SecurityStatus.RECOVERY_REQUIRED)
        }
        return resolved.copy(status = SecurityStatus.LEGACY_MIGRATION_REQUIRED)
    }
}
