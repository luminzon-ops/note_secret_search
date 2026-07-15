package com.example.note_secret_search.security

import java.util.concurrent.atomic.AtomicBoolean

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
    private val operationActive = AtomicBoolean(false)
    private val provisioner = KeyringProvisioner(
        apiLevel = apiLevel,
        envelopeStore = envelopeStore,
        wrappingKeys = wrappingKeys,
        authenticator = authenticator,
        random = random,
    )
    private val unlocker = KeyringUnlocker(
        apiLevel = apiLevel,
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
        val keyAvailable = try {
            wrappingKeys.load(envelope.keyAlias) != null
        } catch (_: WrappingKeyInvalidatedException) {
            false
        } catch (error: KeystoreOperationFailure) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE,
                error,
            )
        }
        return if (keyAvailable) {
            state(
                status = SecurityStatus.LOCKED,
                keyId = keyset.keyId,
                securityLevel = envelope.securityLevel,
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

    override fun lock(): Any? = null

    private fun requiredStateEnvelope(
        keyset: SecurityKeyset,
    ): SecurityEnvelope? {
        val requiredKind = if (apiLevel >= 30) {
            EnvelopeKind.COMBINED
        } else {
            EnvelopeKind.DEVICE_CREDENTIAL
        }
        return keyset.envelopes.firstOrNull { it.kind == requiredKind }
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
        if (!operationActive.compareAndSet(false, true)) {
            result.error(NativeSecurityException(NativeSecurityErrorCode.BUSY))
            return
        }
        val completing = CompletingResult(result) {
            operationActive.set(false)
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

    companion object {
        private const val MAX_REASON_LENGTH = 200
    }
}

internal class CompletingResult<T>(
    private val delegate: NativeResult<T>,
    private val completed: () -> Unit,
) : NativeResult<T> {
    private val terminal = AtomicBoolean(false)

    override fun success(value: T) {
        if (terminal.compareAndSet(false, true)) {
            completed()
            delegate.success(value)
        }
    }

    override fun error(error: NativeSecurityException) {
        if (terminal.compareAndSet(false, true)) {
            completed()
            delegate.error(error)
        }
    }
}
