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

    fun removePin(
        reason: String,
        result: NativeResult<Unit>,
    )

    fun lock(): Any?
}

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

    override fun getSecurityState(): NativeSecurityState = synchronized(operationLock) {
        val auth = capabilities()
        if (legacyDetector.hasLegacyPassword()) {
            return@synchronized state(
                status = SecurityStatus.LEGACY_MIGRATION_REQUIRED,
                auth = auth,
            )
        }
        val encoded = envelopeStore.read()
            ?: return@synchronized state(
                SecurityStatus.UNPROVISIONED,
                auth = auth,
            )
        val keyset = try {
            SecurityKeysetCodec.decode(encoded)
        } catch (_: NativeSecurityException) {
            return@synchronized state(
                SecurityStatus.RECOVERY_REQUIRED,
                auth = auth,
            )
        }
        val envelope = requiredStateEnvelope(keyset)
            ?: return@synchronized state(
                SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
                pinConfigured = keyset.pinEnvelope != null,
                auth = auth,
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
        val resolvedSecurityLevel = handle?.let {
            resolveSecurityLevel(
                stored = envelope.securityLevel,
                loaded = it.securityLevel,
            )
        }
        if (resolvedSecurityLevel != null) {
            state(
                status = SecurityStatus.LOCKED,
                keyId = keyset.keyId,
                pinConfigured = keyset.pinEnvelope != null,
                securityLevel = resolvedSecurityLevel,
                auth = auth,
            )
        } else {
            state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
                pinConfigured = keyset.pinEnvelope != null,
                auth = auth,
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

    override fun provisionWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(reason, result) { operation ->
            if (legacyDetector.hasLegacyPassword()) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.MIGRATION_REQUIRED,
                ))
                return@start
            }
            if (envelopeStore.read() != null) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.INVALID_ARGUMENT,
                ))
                return@start
            }
            val auth = capabilities()
            if (!auth.deviceCredentialAvailable) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
                ))
                return@start
            }
            provisioner.provision(reason, auth, operation)
        }
    }

    override fun unlockWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        start(reason, result) { operation ->
            if (legacyDetector.hasLegacyPassword()) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.MIGRATION_REQUIRED,
                ))
                return@start
            }
            val encoded = envelopeStore.read()
            if (encoded == null) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
                ))
                return@start
            }
            val keyset = try {
                SecurityKeysetCodec.decode(encoded)
            } catch (error: NativeSecurityException) {
                operation.error(error)
                return@start
            }
            unlocker.unlock(reason, keyset, capabilities(), operation)
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
                if (legacyDetector.hasLegacyPassword()) {
                    operation.error(NativeSecurityException(
                        NativeSecurityErrorCode.MIGRATION_REQUIRED,
                    ))
                    return@start
                }
                val encoded = envelopeStore.read()
                if (encoded == null) {
                    operation.error(NativeSecurityException(
                        NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
                    ))
                    return@start
                }
                val keyset = try {
                    SecurityKeysetCodec.decode(encoded)
                } catch (error: NativeSecurityException) {
                    operation.error(error)
                    return@start
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
                if (legacyDetector.hasLegacyPassword()) {
                    operation.error(NativeSecurityException(
                        NativeSecurityErrorCode.MIGRATION_REQUIRED,
                    ))
                    return@start
                }
                val encoded = envelopeStore.read()
                if (encoded == null) {
                    operation.error(NativeSecurityException(
                        NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
                    ))
                    return@start
                }
                val keyset = try {
                    SecurityKeysetCodec.decode(encoded)
                } catch (error: NativeSecurityException) {
                    operation.error(error)
                    return@start
                }
                transferred = true
                pinCoordinator.unlockWithPin(keyset, pin, operation)
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
            if (legacyDetector.hasLegacyPassword()) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.MIGRATION_REQUIRED,
                ))
                return@start
            }
            val encoded = envelopeStore.read()
            if (encoded == null) {
                operation.error(NativeSecurityException(
                    NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED,
                ))
                return@start
            }
            val keyset = try {
                SecurityKeysetCodec.decode(encoded)
            } catch (error: NativeSecurityException) {
                operation.error(error)
                return@start
            }
            pinCoordinator.removePin(reason, keyset, operation)
        }
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

    private fun requiredStateEnvelope(
        keyset: SecurityKeyset,
    ): SecurityEnvelope? {
        return keyset.envelopes.firstOrNull {
            it.kind == EnvelopeKind.COMBINED
        } ?: keyset.envelopes.firstOrNull {
            it.kind == EnvelopeKind.DEVICE_CREDENTIAL
        }
    }

    private fun state(
        status: SecurityStatus,
        keyId: String? = null,
        pinConfigured: Boolean = false,
        securityLevel: KeySecurityLevel = KeySecurityLevel.UNKNOWN,
        auth: SystemAuthCapabilities,
    ): NativeSecurityState {
        return NativeSecurityState(
            status = status,
            keyId = keyId,
            pinConfigured = pinConfigured,
            deviceCredentialAvailable = auth.deviceCredentialAvailable,
            strongBiometricAvailable = auth.strongBiometricAvailable,
            securityLevel = securityLevel,
        )
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
    }
}
