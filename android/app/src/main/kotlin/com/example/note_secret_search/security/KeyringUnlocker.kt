package com.example.note_secret_search.security

import javax.crypto.Cipher

internal class KeyringUnlocker(
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
) {
    fun unlock(
        reason: String,
        keyset: SecurityKeyset,
        capabilities: SystemAuthCapabilities,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        withMasterKey(reason, keyset, capabilities, result) { masterKey ->
            KeyringCrypto.deriveMaterial(keyset.keyId, masterKey)
        }
    }

    fun <T> withMasterKey(
        reason: String,
        keyset: SecurityKeyset,
        capabilities: SystemAuthCapabilities,
        result: NativeResult<T>,
        consume: (ByteArray) -> T,
    ) {
        val combined = envelope(keyset, EnvelopeKind.COMBINED)
        if (combined != null) {
            unlockEnvelope(
                reason,
                keyset.keyId,
                combined,
                result,
                consume,
                result::error,
            )
            return
        }

        val device = envelope(keyset, EnvelopeKind.DEVICE_CREDENTIAL)
        if (device == null) {
            result.error(recoveryRequired())
            return
        }
        val biometric = envelope(keyset, EnvelopeKind.BIOMETRIC)
        if (!capabilities.strongBiometricAvailable || biometric == null) {
            unlockEnvelope(
                reason,
                keyset.keyId,
                device,
                result,
                consume,
                result::error,
            )
            return
        }
        unlockEnvelope(
            reason,
            keyset.keyId,
            biometric,
            result,
            consume,
        ) fallback@{ error ->
            if (!result.isActiveOperation()) {
                return@fallback
            }
            if (shouldFallbackToDeviceCredential(error)) {
                unlockEnvelope(
                    reason,
                    keyset.keyId,
                    device,
                    result,
                    consume,
                    result::error,
                )
            } else {
                result.error(error)
            }
        }
    }

    private fun shouldFallbackToDeviceCredential(
        error: NativeSecurityException,
    ): Boolean {
        return when (error.code) {
            NativeSecurityErrorCode.AUTH_CANCELLED,
            NativeSecurityErrorCode.AUTH_LOCKOUT,
            NativeSecurityErrorCode.KEY_INVALIDATED,
            NativeSecurityErrorCode.ENVELOPE_CORRUPT,
            NativeSecurityErrorCode.RECOVERY_REQUIRED,
            -> true

            else -> false
        }
    }

    private fun <T> unlockEnvelope(
        reason: String,
        keyId: String,
        envelope: SecurityEnvelope,
        result: NativeResult<T>,
        consume: (ByteArray) -> T,
        onError: (NativeSecurityException) -> Unit,
    ) {
        val handle = try {
            wrappingKeys.load(envelope.keyAlias)
        } catch (error: Throwable) {
            onError(KeyringCrypto.mapKeyError(error))
            return
        }
        if (handle == null) {
            onError(recoveryRequired())
            return
        }
        val authPerUse = envelope.kind != EnvelopeKind.DEVICE_CREDENTIAL
        val preparedCipher = if (authPerUse) {
            try {
                handle.decryptionCipher(envelope.nonce)
            } catch (error: Throwable) {
                onError(KeyringCrypto.mapKeyError(error))
                return
            }
        } else {
            null
        }
        val mode = when (envelope.kind) {
            EnvelopeKind.COMBINED -> SystemAuthenticatorMode.COMBINED
            EnvelopeKind.DEVICE_CREDENTIAL -> SystemAuthenticatorMode.DEVICE_CREDENTIAL
            EnvelopeKind.BIOMETRIC -> SystemAuthenticatorMode.BIOMETRIC
        }
        try {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason,
                    mode,
                    preparedCipher,
                    result.operationId(),
                ),
                object : AuthenticationTerminal {
                    override fun succeeded(cipher: Cipher?) {
                        result.runIfActive {
                            var masterKey: ByteArray? = null
                            try {
                                val activeCipher = cipher
                                    ?: handle.decryptionCipher(envelope.nonce)
                                masterKey = try {
                                    KeyringCrypto.unwrap(
                                        keyId,
                                        envelope,
                                        activeCipher,
                                    )
                                } catch (error: Throwable) {
                                    onError(KeyringCrypto.mapUnlockError(error))
                                    return@runIfActive
                                }
                                if (masterKey.size != KeyringCrypto.MASTER_KEY_BYTES) {
                                    onError(NativeSecurityException(
                                        NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                                    ))
                                    return@runIfActive
                                }
                                val consumed = try {
                                    consume(masterKey)
                                } catch (error: NativeSecurityException) {
                                    onError(error)
                                    return@runIfActive
                                } catch (error: Throwable) {
                                    onError(NativeSecurityException(
                                        NativeSecurityErrorCode.INTERNAL_ERROR,
                                        error,
                                    ))
                                    return@runIfActive
                                }
                                result.success(consumed)
                            } finally {
                                masterKey?.fill(0)
                            }
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        result.runIfActive {
                            onError(error)
                        }
                    }
                },
            )
        } catch (error: Throwable) {
            onError(KeyringCrypto.mapKeyError(error))
        }
    }

    private fun envelope(
        keyset: SecurityKeyset,
        kind: EnvelopeKind,
    ): SecurityEnvelope? {
        return keyset.envelopes.firstOrNull { it.kind == kind }
    }

    private fun recoveryRequired(): NativeSecurityException {
        return NativeSecurityException(NativeSecurityErrorCode.RECOVERY_REQUIRED)
    }
}
