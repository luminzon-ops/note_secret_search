package com.example.note_secret_search.security

internal class NativeKeyringManager(
    private val apiLevel: Int,
    private val envelopeStore: SecurityEnvelopeStore,
    private val legacyDetector: LegacySecurityDetector,
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
    private val capabilities: () -> SystemAuthCapabilities,
    random: RandomSource = SecureRandomSource(),
    pinKdfEngine: PinKdfEngine = Argon2KtPinKdfEngine(),
    private val pinWorker: PinWorkScheduler = SerialPinWorkScheduler(),
    pinThrottle: PinAttemptThrottle,
    private val migrationFileCoordinator: MigrationFileCoordinator? = null,
    migrationCompletionVerifier: MigrationCompletionVerifier =
        migrationFileCoordinator ?: MigrationCompletionVerifier { _, _ -> false },
) : NativeKeyringOperations, AutoCloseable {
    private val operationLock = Any()
    private var activeOperation: CompletingResult<*>? = null
    private var nextOperationId = 1L
    private var closed = false
    private val provisioner = KeyringProvisioner(
        apiLevel = apiLevel,
        envelopeStore = envelopeStore,
        wrappingKeys = wrappingKeys,
        authenticator = authenticator,
        random = random,
    )
    private val unlocker = KeyringUnlocker(
        wrappingKeys = wrappingKeys,
        authenticator = authenticator,
    )
    private val pinCoordinator = PinKeyringCoordinator(
        envelopeStore = envelopeStore,
        unlocker = unlocker,
        capabilities = capabilities,
        crypto = PinEnvelopeCrypto(
            keyDeriver = PinKeyDeriver(pinKdfEngine),
            random = random,
        ),
        worker = pinWorker,
        throttle = pinThrottle,
    )
    private val systemRebinder = SystemKeyringRebinder(
        apiLevel = apiLevel,
        envelopeStore = envelopeStore,
        wrappingKeys = wrappingKeys,
        authenticator = authenticator,
    )
    private val migrationCoordinator = MigrationKeyringCoordinator(
        envelopeStore = envelopeStore,
        legacyStore = legacyDetector,
        provisioner = provisioner,
        unlocker = unlocker,
        capabilities = capabilities,
        completionVerifier = migrationCompletionVerifier,
        migrationFiles = migrationFileCoordinator,
    )
    private val stateResolver = NativeSecurityStateResolver(
        apiLevel = apiLevel,
        envelopeStore = envelopeStore,
        legacyDetector = legacyDetector,
        wrappingKeys = wrappingKeys,
        capabilities = capabilities,
        migrationFileCoordinator = migrationFileCoordinator,
    )

    override fun getSecurityState(): NativeSecurityState = synchronized(operationLock) {
        stateResolver.resolve()
    }

    override fun provisionWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(reason, result) { operation ->
            requireNoLegacyMigration()
            if (migrationFileCoordinator?.hasActiveDatabase() == true) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.RECOVERY_REQUIRED,
                )
            }
            if (envelopeStore.read() != null) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.INVALID_ARGUMENT,
                )
            }
            val auth = capabilities()
            if (!auth.deviceCredentialAvailable) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
                )
            }
            provisioner.provision(reason, auth, operation)
        }
    }

    override fun unlockWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(reason, result) { operation ->
            requireNoLegacyMigration()
            unlocker.unlock(
                reason,
                requireKeyset(),
                capabilities(),
                operation,
            )
        }
    }

    override fun configurePin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        start(reason, result, rejected = { pin.fill(0) }) { operation ->
            var transferred = false
            try {
                val keyset = requireKeyset()
                if (
                    legacyDetector.hasLegacyPasswordSafely() &&
                    migrationFileCoordinator
                        ?.isCredentialFinalizationReady(keyset.keyId) != true
                ) {
                    throw NativeSecurityException(
                        NativeSecurityErrorCode.MIGRATION_REQUIRED,
                    )
                }
                transferred = true
                pinCoordinator.configurePin(reason, keyset, pin, operation)
            } finally {
                if (!transferred) {
                    pin.fill(0)
                }
            }
        }
    }

    override fun unlockWithPin(
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(PIN_UNLOCK_OPERATION, result, rejected = { pin.fill(0) }) { operation ->
            var transferred = false
            try {
                requireNoLegacyMigration()
                val keyset = requireUsablePinKeyset()
                transferred = true
                pinCoordinator.unlockWithPin(keyset, pin, operation)
            } finally {
                if (!transferred) {
                    pin.fill(0)
                }
            }
        }
    }

    override fun rebindSystemAuthWithPin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        start(reason, result, rejected = { pin.fill(0) }) { operation ->
            var transferred = false
            try {
                requireNoLegacyMigration()
                val keyset = requireUsablePinKeyset()
                transferred = true
                pinCoordinator.rebindSystemAuthWithPin(
                    reason = reason,
                    keyset = keyset,
                    pin = pin,
                    rebinder = systemRebinder,
                    result = operation,
                )
            } finally {
                if (!transferred) {
                    pin.fill(0)
                }
            }
        }
    }

    override fun removePin(
        reason: String,
        result: NativeResult<Unit>,
    ) {
        start(reason, result) { operation ->
            requireNoLegacyMigration()
            pinCoordinator.removePin(reason, requireKeyset(), operation)
        }
    }

    override fun beginLegacyMigration(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(reason, result) { operation ->
            migrationCoordinator.begin(reason, operation)
        }
    }

    override fun getLegacyMigrationState(): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().inspectState()

    override fun prepareLegacyMigrationBackup(keyId: String): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().prepareBackupState(keyId)

    override fun prepareLegacyMigrationPending(keyId: String): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().preparePendingState(keyId)

    override fun markLegacyMigrationRowsCopied(keyId: String): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().markRowsCopiedState(keyId)

    override fun markLegacyMigrationValidated(keyId: String): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().markValidatedState(keyId)

    override fun activateLegacyMigration(keyId: String): Map<String, Any?> {
        return migrationFileCoordinator.requireConfigured().activateState(keyId)
    }

    override fun markLegacyMigrationPostSwapValidated(
        keyId: String,
    ): Map<String, Any?> {
        return migrationFileCoordinator.requireConfigured()
            .markPostSwapValidatedState(keyId)
    }

    override fun cleanupLegacyMigrationFiles(keyId: String): Map<String, Any?> =
        migrationFileCoordinator.requireConfigured().cleanupState(keyId)

    override fun finishLegacyMigration(keyId: String) =
        migrationCoordinator.finish(keyId)

    override fun commitLegacyMigration(
        keyId: String,
        activeDigest: String,
        result: NativeResult<Unit>,
    ) {
        start(MIGRATION_COMMIT_OPERATION, result) { operation ->
            migrationCoordinator.commit(keyId, activeDigest, operation)
        }
    }

    override fun abortLegacyMigration(result: NativeResult<Unit>) {
        cancelActiveOperation()
        result.success(Unit)
    }

    override fun lock(): Any? {
        cancelActiveOperation()
        return null
    }

    override fun close() {
        val shouldClose = synchronized(operationLock) {
            if (closed) {
                false
            } else {
                closed = true
                true
            }
        }
        if (!shouldClose) {
            return
        }
        cancelActiveOperation()
        try {
            pinWorker.close()
        } catch (_: Throwable) {
            // Operation material is already revoked.
        }
    }

    private fun cancelActiveOperation() {
        val operation = synchronized(operationLock) {
            val active = activeOperation ?: return
            activeOperation = null
            active
        }
        operation.cancelLocked()
        try {
            authenticator.cancel(operation.operationId)
        } catch (_: Throwable) {
            // The operation is already revoked and its sensitive buffers cleared.
        }
    }

    private fun <T> start(
        reason: String,
        result: NativeResult<T>,
        rejected: () -> Unit = {},
        operation: (CompletingResult<T>) -> Unit,
    ) {
        if (reason.isBlank() || reason.length > MAX_REASON_LENGTH) {
            rejected()
            result.error(NativeSecurityException(
                NativeSecurityErrorCode.INVALID_ARGUMENT,
            ))
            return
        }
        lateinit var completing: CompletingResult<T>
        synchronized(operationLock) {
            if (closed) {
                rejected()
                result.error(NativeSecurityException(
                    NativeSecurityErrorCode.AUTH_CANCELLED,
                ))
                return
            }
            if (activeOperation != null) {
                rejected()
                result.error(NativeSecurityException(NativeSecurityErrorCode.BUSY))
                return
            }
            completing = CompletingResult(
                operationId = nextOperationId++,
                delegate = result,
                complete = ::complete,
                isActive = ::isActive,
                registerCleanupDelegate = ::registerCancellationCleanup,
                runIfActiveDelegate = ::runIfActive,
            )
            activeOperation = completing
        }
        try {
            runIfActive(completing) {
                operation(completing)
            }
        } catch (error: Throwable) {
            completing.error(
                error as? NativeSecurityException
                    ?: NativeSecurityException(
                        NativeSecurityErrorCode.INTERNAL_ERROR,
                        error,
                    ),
            )
        }
    }

    private fun requireNoLegacyMigration() {
        if (legacyDetector.hasLegacyPasswordSafely()) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_REQUIRED,
            )
        }
    }

    private fun requireKeyset(): SecurityKeyset {
        return envelopeStore.readRecoverableKeyset()
            ?: throw NativeSecurityException(
                NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
            )
    }

    private fun requireUsablePinKeyset(): SecurityKeyset {
        return requireKeyset().also { keyset ->
            if (keyset.pinResetRequired) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                )
            }
        }
    }

    private fun <T> complete(
        owner: CompletingResult<T>,
        delivery: () -> Unit,
    ): CompletionOutcome {
        return synchronized(operationLock) {
            if (activeOperation !== owner) {
                return@synchronized CompletionOutcome.INACTIVE
            }
            activeOperation = null
            owner.discardCancellationCleanups()
            try {
                delivery()
                CompletionOutcome.DELIVERED
            } catch (_: Throwable) {
                CompletionOutcome.DELIVERY_FAILED
            }
        }
    }

    private fun <T> isActive(owner: CompletingResult<T>): Boolean {
        return synchronized(operationLock) {
            activeOperation === owner
        }
    }

    private fun <T> registerCancellationCleanup(
        owner: CompletingResult<T>,
        cleanup: () -> Unit,
    ): Boolean {
        return synchronized(operationLock) {
            if (activeOperation !== owner) {
                return@synchronized false
            }
            owner.addCancellationCleanup(cleanup)
            true
        }
    }

    private fun <T> runIfActive(
        owner: CompletingResult<T>,
        operation: () -> Unit,
    ): Boolean {
        return synchronized(operationLock) {
            if (activeOperation !== owner) {
                return@synchronized false
            }
            operation()
            true
        }
    }

    companion object {
        private const val MAX_REASON_LENGTH = 200
        private const val PIN_UNLOCK_OPERATION = "PIN unlock"
        private const val MIGRATION_COMMIT_OPERATION = "Migration commit"
    }
}
