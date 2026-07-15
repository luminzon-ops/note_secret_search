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

    override fun getSecurityState(): NativeSecurityState {
        val auth = capabilities()
        if (legacyDetector.hasLegacyPassword()) {
            return state(
                status = SecurityStatus.LEGACY_MIGRATION_REQUIRED,
                auth = auth,
            )
        }
        val encoded = envelopeStore.read()
            ?: return state(SecurityStatus.UNPROVISIONED, auth = auth)
        val keyset = try {
            SecurityKeysetCodec.decode(encoded)
        } catch (_: NativeSecurityException) {
            return state(SecurityStatus.RECOVERY_REQUIRED, auth = auth)
        }
        val envelope = requiredStateEnvelope(keyset)
            ?: return state(
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
        return if (resolvedSecurityLevel != null) {
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
        try {
            authenticator.cancel()
        } catch (_: Throwable) {
            // The operation is still revoked even if the platform prompt is gone.
        } finally {
            operation.cancelLocked()
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
        val completing = CompletingResult(
            delegate = result,
            complete = ::complete,
            isActive = ::isActive,
        )
        synchronized(operationLock) {
            if (activeOperation != null) {
                result.error(NativeSecurityException(NativeSecurityErrorCode.BUSY))
                return
            }
            activeOperation = completing
        }
        try {
            operation(completing)
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
    ): Boolean {
        return synchronized(operationLock) {
            if (activeOperation !== owner) {
                return@synchronized false
            }
            activeOperation = null
            delivery()
            true
        }
    }

    private fun <T> isActive(owner: CompletingResult<T>): Boolean {
        return synchronized(operationLock) {
            activeOperation === owner
        }
    }

    companion object {
        private const val MAX_REASON_LENGTH = 200
    }
}

internal class CompletingResult<T>(
    private val delegate: NativeResult<T>,
    private val complete: (CompletingResult<T>, () -> Unit) -> Boolean,
    private val isActive: (CompletingResult<T>) -> Boolean,
) : NativeResult<T>, OperationAwareResult {
    override fun isActiveOperation(): Boolean = isActive(this)

    override fun success(value: T) {
        val delivered = complete(this) {
            delegate.success(value)
        }
        if (!delivered && value is NativeUnlockMaterial) {
            value.zeroize()
        }
    }

    override fun error(error: NativeSecurityException) {
        complete(this) {
            delegate.error(error)
        }
    }

    fun cancelLocked() {
        delegate.error(NativeSecurityException(
            NativeSecurityErrorCode.AUTH_CANCELLED,
        ))
    }
}

internal interface OperationAwareResult {
    fun isActiveOperation(): Boolean
}

internal fun NativeResult<*>.isActiveOperation(): Boolean {
    return (this as? OperationAwareResult)?.isActiveOperation() ?: true
}
