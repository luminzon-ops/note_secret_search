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
        val generatedAliases = if (apiLevel >= 30) {
            listOf(KeyringCrypto.alias(keyId, EnvelopeKind.COMBINED))
        } else {
            buildList {
                add(KeyringCrypto.alias(keyId, EnvelopeKind.DEVICE_CREDENTIAL))
                if (capabilities.strongBiometricAvailable) {
                    add(KeyringCrypto.alias(keyId, EnvelopeKind.BIOMETRIC))
                }
            }
        }
        if (!result.registerCancellationCleanup {
                generatedAliases.forEach {
                    KeyringCrypto.cleanupAlias(wrappingKeys, it)
                }
                masterKey.fill(0)
            }
        ) {
            generatedAliases.forEach {
                KeyringCrypto.cleanupAlias(wrappingKeys, it)
            }
            masterKey.fill(0)
            return
        }
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
        val preparedCipher = try {
            handle.encryptionCipher()
        } catch (error: Throwable) {
            failRequired(alias, masterKey, result, error)
            return
        }
        authenticateRequired(
            request = SystemAuthRequest(
                reason,
                SystemAuthenticatorMode.COMBINED,
                preparedCipher,
                result.operationId(),
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
            onSuccess = { authenticatedCipher ->
                if (!result.isActiveOperation()) {
                    KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                    masterKey.fill(0)
                    return@authenticateRequired
                }
                val envelope = KeyringCrypto.wrap(
                    keyId,
                    kind,
                    alias,
                    handle.securityLevel,
                    authenticatedCipher ?: preparedCipher,
                    masterKey,
                )
                completeSuccess(
                    keyId,
                    masterKey,
                    SecurityKeyset(keyId, listOf(envelope)),
                    result,
                )
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
                operationId = result.operationId(),
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
            onSuccess = {
                if (!result.isActiveOperation()) {
                    KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                    masterKey.fill(0)
                    return@authenticateRequired
                }
                val envelope = KeyringCrypto.wrap(
                    keyId,
                    kind,
                    alias,
                    handle.securityLevel,
                    handle.encryptionCipher(),
                    masterKey,
                )
                val deviceKeyset = SecurityKeyset(keyId, listOf(envelope))
                if (strongBiometricAvailable) {
                    provisionOptionalBiometric(
                        reason,
                        keyId,
                        masterKey,
                        deviceKeyset,
                        result,
                    )
                } else {
                    completeSuccess(keyId, masterKey, deviceKeyset, result)
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
            completeSuccess(keyId, masterKey, deviceKeyset, result)
            return
        }
        val preparedCipher = try {
            handle.encryptionCipher()
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(keyId, masterKey, deviceKeyset, result)
            return
        }
        try {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason,
                    SystemAuthenticatorMode.BIOMETRIC,
                    preparedCipher,
                    result.operationId(),
                ),
                object : AuthenticationTerminal {
                    override fun succeeded(cipher: Cipher?) {
                        result.runIfActive {
                            val envelope = try {
                                KeyringCrypto.wrap(
                                    keyId,
                                    kind,
                                    alias,
                                    handle.securityLevel,
                                    cipher ?: preparedCipher,
                                    masterKey,
                                )
                            } catch (_: Throwable) {
                                KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                                completeSuccess(
                                    keyId,
                                    masterKey,
                                    deviceKeyset,
                                    result,
                                )
                                return@runIfActive
                            }
                            completeSuccess(
                                keyId,
                                masterKey,
                                deviceKeyset.copy(
                                    envelopes = deviceKeyset.envelopes + envelope,
                                ),
                                result,
                                fallbackKeyset = deviceKeyset,
                            )
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        result.runIfActive {
                            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                            completeSuccess(
                                keyId,
                                masterKey,
                                deviceKeyset,
                                result,
                            )
                        }
                    }
                },
            )
        } catch (_: Throwable) {
            result.runIfActive {
                KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                completeSuccess(keyId, masterKey, deviceKeyset, result)
            }
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
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
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
                        result.runIfActive {
                            try {
                                onSuccess(cipher)
                            } catch (error: Throwable) {
                                failRequired(alias, masterKey, result, error)
                            }
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        result.runIfActive {
                            failRequired(alias, masterKey, result, error)
                        }
                    }
                },
            )
        } catch (error: Throwable) {
            result.runIfActive {
                failRequired(alias, masterKey, result, error)
            }
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
        keyset: SecurityKeyset,
        result: NativeResult<NativeUnlockMaterial>,
        fallbackKeyset: SecurityKeyset? = null,
    ) {
        var material: NativeUnlockMaterial? = null
        try {
            val unlockMaterial = KeyringCrypto.deriveMaterial(keyId, masterKey)
            material = unlockMaterial
            val committed = result.runIfActive {
                try {
                    envelopeStore.write(SecurityKeysetCodec.encode(keyset))
                } catch (error: Throwable) {
                    val fallback = fallbackKeyset ?: throw error
                    val retainedAliases = fallback.envelopes
                        .mapTo(mutableSetOf()) { it.keyAlias }
                    keyset.envelopes
                        .filterNot { it.keyAlias in retainedAliases }
                        .forEach {
                            KeyringCrypto.cleanupAlias(
                                wrappingKeys,
                                it.keyAlias,
                            )
                        }
                    envelopeStore.write(SecurityKeysetCodec.encode(fallback))
                }
                result.success(unlockMaterial)
            }
            if (!committed) {
                unlockMaterial.zeroize()
                keyset.envelopes.forEach {
                    KeyringCrypto.cleanupAlias(wrappingKeys, it.keyAlias)
                }
            }
        } catch (error: Throwable) {
            material?.zeroize()
            keyset.envelopes.forEach {
                KeyringCrypto.cleanupAlias(wrappingKeys, it.keyAlias)
            }
            result.error(KeyringCrypto.mapKeyError(error))
        } finally {
            masterKey.fill(0)
        }
    }
}
