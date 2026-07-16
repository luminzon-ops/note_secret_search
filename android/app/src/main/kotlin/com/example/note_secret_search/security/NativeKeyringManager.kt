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

    fun lock(): Any?
}

class NativeKeyringManager(
    private val apiLevel: Int,
    private val envelopeStore: SecurityEnvelopeStore,
    private val legacyDetector: LegacySecurityDetector,
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
    private val capabilities: () -> SystemAuthCapabilities,
    random: RandomSource = SecureRandomSource(),
) : NativeKeyringOperations {
    private val operationLock = Any()
    private var activeOperation: CompletingResult<*>? = null
    private var nextOperationId = 1L
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
                securityLevel = resolvedSecurityLevel,
                auth = auth,
            )
        } else {
            state(
                status = SecurityStatus.RECOVERY_REQUIRED,
                keyId = keyset.keyId,
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

    override fun lock(): Any? {
        val operation = synchronized(operationLock) {
            val active = activeOperation ?: return null
            activeOperation = null
            active
        }
        operation.cancelLocked()
        try {
            authenticator.cancel(operation.operationId)
        } catch (_: Throwable) {
            // The operation is already revoked and its sensitive buffers cleared.
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

    private fun state(
        status: SecurityStatus,
        keyId: String? = null,
        securityLevel: KeySecurityLevel = KeySecurityLevel.UNKNOWN,
        auth: SystemAuthCapabilities,
    ): NativeSecurityState {
        return NativeSecurityState(
            status = status,
            keyId = keyId,
            deviceCredentialAvailable = auth.deviceCredentialAvailable,
            strongBiometricAvailable = auth.strongBiometricAvailable,
            securityLevel = securityLevel,
        )
    }

    private fun <T> start(
        reason: String,
        result: NativeResult<T>,
        operation: (CompletingResult<T>) -> Unit,
    ) {
        if (reason.isBlank() || reason.length > MAX_REASON_LENGTH) {
            result.error(NativeSecurityException(
                NativeSecurityErrorCode.INVALID_ARGUMENT,
            ))
            return
        }
        lateinit var completing: CompletingResult<T>
        synchronized(operationLock) {
            if (activeOperation != null) {
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
    }
}

internal class CompletingResult<T>(
    override val operationId: Long,
    private val delegate: NativeResult<T>,
    private val complete: (
        CompletingResult<T>,
        () -> Unit,
    ) -> CompletionOutcome,
    private val isActive: (CompletingResult<T>) -> Boolean,
    private val registerCleanupDelegate: (
        CompletingResult<T>,
        () -> Unit,
    ) -> Boolean,
    private val runIfActiveDelegate: (CompletingResult<T>, () -> Unit) -> Boolean,
) : NativeResult<T>, OperationAwareResult {
    private val cancellationCleanups = mutableListOf<() -> Unit>()

    override fun isActiveOperation(): Boolean = isActive(this)

    override fun registerCancellationCleanup(cleanup: () -> Unit): Boolean {
        return registerCleanupDelegate(this, cleanup)
    }

    override fun runIfActive(operation: () -> Unit): Boolean {
        return runIfActiveDelegate(this, operation)
    }

    override fun success(value: T) {
        val outcome = complete(this) {
            delegate.success(value)
        }
        if (outcome != CompletionOutcome.DELIVERED && value is NativeUnlockMaterial) {
            value.zeroize()
        }
    }

    override fun error(error: NativeSecurityException) {
        complete(this) {
            delegate.error(error)
        }
    }

    fun cancelLocked() {
        val cleanups = cancellationCleanups.toList()
        cancellationCleanups.clear()
        cleanups.forEach { cleanup ->
            try {
                cleanup()
            } catch (_: Throwable) {
                // Continue clearing the remaining operation-owned material.
            }
        }
        try {
            delegate.error(NativeSecurityException(
                NativeSecurityErrorCode.AUTH_CANCELLED,
            ))
        } catch (_: Throwable) {
            // Transport failures must not skip prompt cancellation.
        }
    }

    fun addCancellationCleanup(cleanup: () -> Unit) {
        cancellationCleanups += cleanup
    }

    fun discardCancellationCleanups() {
        cancellationCleanups.clear()
    }
}

internal enum class CompletionOutcome {
    INACTIVE,
    DELIVERED,
    DELIVERY_FAILED,
}

internal interface OperationAwareResult {
    val operationId: Long

    fun isActiveOperation(): Boolean

    fun registerCancellationCleanup(cleanup: () -> Unit): Boolean

    fun runIfActive(operation: () -> Unit): Boolean
}

internal fun NativeResult<*>.isActiveOperation(): Boolean {
    return (this as? OperationAwareResult)?.isActiveOperation() ?: true
}

internal fun NativeResult<*>.operationId(): Long {
    return (this as? OperationAwareResult)?.operationId ?: 0
}

internal fun NativeResult<*>.registerCancellationCleanup(
    cleanup: () -> Unit,
): Boolean {
    return (this as? OperationAwareResult)
        ?.registerCancellationCleanup(cleanup)
        ?: true
}

internal fun NativeResult<*>.runIfActive(operation: () -> Unit): Boolean {
    return (this as? OperationAwareResult)?.runIfActive(operation)
        ?: run {
            operation()
            true
        }
}
