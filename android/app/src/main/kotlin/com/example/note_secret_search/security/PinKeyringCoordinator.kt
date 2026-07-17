package com.example.note_secret_search.security

internal class PinKeyringCoordinator(
    private val envelopeStore: SecurityEnvelopeStore,
    private val unlocker: KeyringUnlocker,
    private val capabilities: () -> SystemAuthCapabilities,
    private val crypto: PinEnvelopeCrypto,
    private val worker: PinWorkScheduler,
    private val throttle: PinAttemptThrottle,
) {
    fun configurePin(
        reason: String,
        keyset: SecurityKeyset,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        if (!isValidPin(pin)) {
            pin.fill(0)
            result.error(
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        try {
            val handle = worker.execute {
                prepareAndAuthenticate(reason, keyset, pin, result)
            }
            if (!result.registerCancellationCleanup {
                    handle.cancel()
                    pin.fill(0)
                }
            ) {
                handle.cancel()
                pin.fill(0)
            }
        } catch (error: Throwable) {
            pin.fill(0)
            result.error(KeyringCrypto.mapKeyError(error))
        }
    }

    fun unlockWithPin(
        keyset: SecurityKeyset,
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val envelope = keyset.pinEnvelope
        if (envelope == null || !isValidPin(pin)) {
            pin.fill(0)
            result.error(
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        val pinGeneration = PinEnvelopeGeneration.create(
            keyId = keyset.keyId,
            envelope = envelope,
        )
        try {
            throttle.checkAllowed(pinGeneration)
        } catch (error: Throwable) {
            pin.fill(0)
            result.error(KeyringCrypto.mapKeyError(error))
            return
        }
        try {
            val handle = worker.execute {
                unlockOnWorker(
                    keyset = keyset,
                    envelope = envelope,
                    pinGeneration = pinGeneration,
                    pin = pin,
                    result = result,
                )
            }
            if (!result.registerCancellationCleanup {
                    handle.cancel()
                    pin.fill(0)
                }
            ) {
                handle.cancel()
                pin.fill(0)
            }
        } catch (error: Throwable) {
            pin.fill(0)
            result.error(KeyringCrypto.mapKeyError(error))
        }
    }

    fun removePin(
        reason: String,
        keyset: SecurityKeyset,
        result: NativeResult<Unit>,
    ) {
        unlocker.withMasterKey(
            reason = reason,
            keyset = keyset,
            capabilities = capabilities(),
            result = result,
        ) {
            if (keyset.pinEnvelope != null) {
                envelopeStore.write(
                    SecurityKeysetCodec.encode(
                        keyset.copy(pinEnvelope = null),
                    ),
                )
            }
            Unit
        }
    }

    private fun prepareAndAuthenticate(
        reason: String,
        keyset: SecurityKeyset,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        var prepared: PreparedPinKey? = null
        try {
            prepared = crypto.prepare(pin)
            val preparedKey = prepared
            if (!result.registerCancellationCleanup(preparedKey::clear)) {
                preparedKey.clear()
                return
            }
            result.runIfActive {
                unlocker.withMasterKey(
                    reason = reason,
                    keyset = keyset,
                    capabilities = capabilities(),
                    result = ClearingNativeResult(result, preparedKey::clear),
                ) { masterKey ->
                    val pinEnvelope = crypto.wrap(
                        keyId = keyset.keyId,
                        masterKey = masterKey,
                        prepared = preparedKey,
                    )
                    envelopeStore.write(
                        SecurityKeysetCodec.encode(
                            keyset.copy(pinEnvelope = pinEnvelope),
                        ),
                    )
                    Unit
                }
            }
        } catch (error: Throwable) {
            prepared?.clear()
            result.runIfActive {
                result.error(KeyringCrypto.mapKeyError(error))
            }
        }
    }

    private fun unlockOnWorker(
        keyset: SecurityKeyset,
        envelope: PinEnvelope,
        pinGeneration: String,
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        var masterKey: ByteArray? = null
        var material: NativeUnlockMaterial? = null
        try {
            masterKey = crypto.unwrap(keyset.keyId, envelope, pin)
            if (masterKey.size != KeyringCrypto.MASTER_KEY_BYTES) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                )
            }
            val unlockMaterial = KeyringCrypto.deriveMaterial(
                keyId = keyset.keyId,
                masterKey = masterKey,
                unlockMethod = "pin",
            )
            material = unlockMaterial
            var materialDelivered = false
            val delivered = result.runIfActive {
                val throttleError = try {
                    throttle.recordSuccess(pinGeneration)
                    null
                } catch (error: Throwable) {
                    KeyringCrypto.mapKeyError(error)
                }
                if (throttleError == null) {
                    result.success(unlockMaterial)
                    materialDelivered = true
                } else {
                    result.error(throttleError)
                }
            }
            if (delivered && materialDelivered) {
                material = null
            }
        } catch (error: Throwable) {
            val mapped = KeyringCrypto.mapKeyError(error)
            result.runIfActive {
                val throttleError = if (
                    mapped.code == NativeSecurityErrorCode.PIN_INCORRECT
                ) {
                    try {
                        throttle.recordFailure(pinGeneration)
                        null
                    } catch (storageError: Throwable) {
                        KeyringCrypto.mapKeyError(storageError)
                    }
                } else {
                    null
                }
                result.error(throttleError ?: mapped)
            }
        } finally {
            masterKey?.fill(0)
            material?.zeroize()
            pin.fill(0)
        }
    }

    private fun isValidPin(pin: ByteArray): Boolean {
        return pin.size in MIN_PIN_BYTES..MAX_PIN_BYTES &&
            pin.all { it in ASCII_ZERO..ASCII_NINE }
    }

    companion object {
        private const val MIN_PIN_BYTES = 4
        private const val MAX_PIN_BYTES = 8
        private const val ASCII_ZERO = 0x30.toByte()
        private const val ASCII_NINE = 0x39.toByte()
    }
}

private class ClearingNativeResult<T>(
    private val delegate: NativeResult<T>,
    private val cleanup: () -> Unit,
) : NativeResult<T>, OperationAwareResult {
    override val operationId: Long
        get() = delegate.operationId()

    override fun isActiveOperation(): Boolean {
        return delegate.isActiveOperation()
    }

    override fun registerCancellationCleanup(cleanup: () -> Unit): Boolean {
        return delegate.registerCancellationCleanup(cleanup)
    }

    override fun runIfActive(operation: () -> Unit): Boolean {
        return delegate.runIfActive(operation)
    }

    override fun success(value: T) {
        cleanup()
        delegate.success(value)
    }

    override fun error(error: NativeSecurityException) {
        cleanup()
        delegate.error(error)
    }
}
