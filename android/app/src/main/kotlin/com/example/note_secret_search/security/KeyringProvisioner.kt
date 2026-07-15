package com.example.note_secret_search.security

import javax.crypto.Cipher

internal class KeyringProvisioner(
    private val apiLevel: Int,
    private val envelopeStore: SecurityEnvelopeStore,
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
    private val random: RandomSource,
) {
    fun provision(
        reason: String,
        capabilities: SystemAuthCapabilities,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val keyId = KeyringCrypto.randomUuid(random)
        val masterKey = random.bytes(KeyringCrypto.MASTER_KEY_BYTES)
        if (apiLevel >= 30) {
            provisionCombined(reason, keyId, masterKey, result)
        } else {
            provisionDeviceCredential(
                reason,
                keyId,
                masterKey,
                capabilities.strongBiometricAvailable,
                result,
            )
        }
    }

    private fun provisionCombined(
        reason: String,
        keyId: String,
        masterKey: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val kind = EnvelopeKind.COMBINED
        val alias = KeyringCrypto.alias(keyId, kind)
        val handle = createRequiredKey(
            alias,
            WrappingKeyPolicy.COMBINED_AUTH_PER_USE,
            masterKey,
            result,
        ) ?: return
        val cipher = try {
            handle.encryptionCipher()
        } catch (error: Throwable) {
            failRequired(alias, masterKey, result, error)
            return
        }
        authenticateRequired(
            request = SystemAuthRequest(
                reason,
                SystemAuthenticatorMode.COMBINED,
                cipher,
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
            onSuccess = { authenticatedCipher ->
                val envelope = KeyringCrypto.wrap(
                    keyId,
                    kind,
                    alias,
                    handle.securityLevel,
                    authenticatedCipher ?: cipher,
                    masterKey,
                )
                envelopeStore.write(SecurityKeysetCodec.encode(
                    SecurityKeyset(keyId, listOf(envelope)),
                ))
                completeSuccess(keyId, masterKey, result)
            },
        )
    }

    private fun provisionDeviceCredential(
        reason: String,
        keyId: String,
        masterKey: ByteArray,
        strongBiometricAvailable: Boolean,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val kind = EnvelopeKind.DEVICE_CREDENTIAL
        val alias = KeyringCrypto.alias(keyId, kind)
        val handle = createRequiredKey(
            alias,
            WrappingKeyPolicy.DEVICE_CREDENTIAL_WINDOW,
            masterKey,
            result,
        ) ?: return
        authenticateRequired(
            request = SystemAuthRequest(
                reason,
                SystemAuthenticatorMode.DEVICE_CREDENTIAL,
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
            onSuccess = {
                val envelope = KeyringCrypto.wrap(
                    keyId,
                    kind,
                    alias,
                    handle.securityLevel,
                    handle.encryptionCipher(),
                    masterKey,
                )
                val deviceKeyset = SecurityKeyset(keyId, listOf(envelope))
                envelopeStore.write(SecurityKeysetCodec.encode(deviceKeyset))
                if (strongBiometricAvailable) {
                    provisionOptionalBiometric(
                        reason,
                        keyId,
                        masterKey,
                        deviceKeyset,
                        result,
                    )
                } else {
                    completeSuccess(keyId, masterKey, result)
                }
            },
        )
    }

    private fun provisionOptionalBiometric(
        reason: String,
        keyId: String,
        masterKey: ByteArray,
        deviceKeyset: SecurityKeyset,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val kind = EnvelopeKind.BIOMETRIC
        val alias = KeyringCrypto.alias(keyId, kind)
        val handle = try {
            wrappingKeys.create(alias, WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE)
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(keyId, masterKey, result)
            return
        }
        val cipher = try {
            handle.encryptionCipher()
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(keyId, masterKey, result)
            return
        }
        try {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason,
                    SystemAuthenticatorMode.BIOMETRIC,
                    cipher,
                ),
                object : AuthenticationTerminal {
                    override fun succeeded(authenticatedCipher: Cipher?) {
                        val envelope = try {
                            KeyringCrypto.wrap(
                                keyId,
                                kind,
                                alias,
                                handle.securityLevel,
                                authenticatedCipher ?: cipher,
                                masterKey,
                            )
                        } catch (_: Throwable) {
                            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                            completeSuccess(keyId, masterKey, result)
                            return
                        }
                        try {
                            envelopeStore.write(SecurityKeysetCodec.encode(
                                deviceKeyset.copy(
                                    envelopes = deviceKeyset.envelopes + envelope,
                                ),
                            ))
                        } catch (_: Throwable) {}
                        completeSuccess(keyId, masterKey, result)
                    }

                    override fun failed(error: NativeSecurityException) {
                        KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                        completeSuccess(keyId, masterKey, result)
                    }
                },
            )
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(keyId, masterKey, result)
        }
    }

    private fun createRequiredKey(
        alias: String,
        policy: WrappingKeyPolicy,
        masterKey: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ): WrappingKeyHandle? {
        return try {
            wrappingKeys.create(alias, policy)
        } catch (error: Throwable) {
            masterKey.fill(0)
            result.error(KeyringCrypto.mapKeyError(error))
            null
        }
    }

    private fun authenticateRequired(
        request: SystemAuthRequest,
        alias: String,
        masterKey: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
        onSuccess: (Cipher?) -> Unit,
    ) {
        try {
            authenticator.authenticate(
                request,
                object : AuthenticationTerminal {
                    override fun succeeded(cipher: Cipher?) {
                        try {
                            onSuccess(cipher)
                        } catch (error: Throwable) {
                            failRequired(alias, masterKey, result, error)
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        failRequired(alias, masterKey, result, error)
                    }
                },
            )
        } catch (error: Throwable) {
            failRequired(alias, masterKey, result, error)
        }
    }

    private fun failRequired(
        alias: String,
        masterKey: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
        error: Throwable,
    ) {
        KeyringCrypto.cleanupAlias(wrappingKeys, alias)
        masterKey.fill(0)
        result.error(KeyringCrypto.mapKeyError(error))
    }

    private fun completeSuccess(
        keyId: String,
        masterKey: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        val material = KeyringCrypto.deriveMaterial(keyId, masterKey)
        masterKey.fill(0)
        result.success(material)
    }
}
