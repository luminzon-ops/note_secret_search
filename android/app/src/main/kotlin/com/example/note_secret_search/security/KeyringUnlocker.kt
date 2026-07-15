package com.example.note_secret_search.security

import javax.crypto.Cipher

internal class KeyringUnlocker(
    private val apiLevel: Int,
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
) {
    fun unlock(
        reason: String,
        keyset: SecurityKeyset,
        capabilities: SystemAuthCapabilities,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        if (apiLevel >= 30) {
            val combined = envelope(keyset, EnvelopeKind.COMBINED)
            if (combined == null) {
                result.error(recoveryRequired())
                return
            }
            unlockEnvelope(reason, keyset.keyId, combined, result, result::error)
            return
        }

        val device = envelope(keyset, EnvelopeKind.DEVICE_CREDENTIAL)
        if (device == null) {
            result.error(recoveryRequired())
            return
        }
        val biometric = envelope(keyset, EnvelopeKind.BIOMETRIC)
        if (!capabilities.strongBiometricAvailable || biometric == null) {
            unlockEnvelope(reason, keyset.keyId, device, result, result::error)
            return
        }
        unlockEnvelope(
            reason,
            keyset.keyId,
            biometric,
            result,
        ) { error ->
            if (error.code == NativeSecurityErrorCode.AUTH_CANCELLED) {
                unlockEnvelope(
                    reason,
                    keyset.keyId,
                    device,
                    result,
                    result::error,
                )
            } else {
                result.error(error)
            }
        }
    }

    private fun unlockEnvelope(
        reason: String,
        keyId: String,
        envelope: SecurityEnvelope,
        result: NativeResult<NativeUnlockMaterial>,
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
                SystemAuthRequest(reason, mode, preparedCipher),
                object : AuthenticationTerminal {
                    override fun succeeded(cipher: Cipher?) {
                        var masterKey: ByteArray? = null
                        try {
                            val activeCipher = cipher
                                ?: handle.decryptionCipher(envelope.nonce)
                            masterKey = KeyringCrypto.unwrap(
                                keyId,
                                envelope,
                                activeCipher,
                            )
                            if (masterKey.size != KeyringCrypto.MASTER_KEY_BYTES) {
                                throw NativeSecurityException(
                                    NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                                )
                            }
                            result.success(
                                KeyringCrypto.deriveMaterial(keyId, masterKey),
                            )
                        } catch (error: Throwable) {
                            onError(KeyringCrypto.mapUnlockError(error))
                        } finally {
                            masterKey?.fill(0)
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        onError(error)
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
