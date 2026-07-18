package com.example.note_secret_search.security

import javax.crypto.Cipher

internal class SystemKeyringRebinder(
    private val apiLevel: Int,
    private val envelopeStore: SecurityEnvelopeStore,
    private val wrappingKeys: WrappingKeyRepository,
    private val authenticator: SystemAuthenticator,
) {
    fun rebind(
        reason: String,
        keyset: SecurityKeyset,
        masterKey: ByteArray,
        capabilities: SystemAuthCapabilities,
        result: NativeResult<Unit>,
    ) {
        if (masterKey.size != KeyringCrypto.MASTER_KEY_BYTES) {
            masterKey.fill(0)
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.ENVELOPE_CORRUPT,
                ),
            )
            return
        }
        if (!capabilities.deviceCredentialAvailable) {
            masterKey.fill(0)
            result.error(
                NativeSecurityException(
                    NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET,
                ),
            )
            return
        }

        val aliases = expectedAliases(keyset.keyId, capabilities)
        if (!result.registerCancellationCleanup {
                aliases.forEach { KeyringCrypto.cleanupAlias(wrappingKeys, it) }
                masterKey.fill(0)
            }
        ) {
            aliases.forEach { KeyringCrypto.cleanupAlias(wrappingKeys, it) }
            masterKey.fill(0)
            return
        }
        keyset.envelopes.forEach {
            KeyringCrypto.cleanupAlias(wrappingKeys, it.keyAlias)
        }

        if (apiLevel >= 30) {
            rebindCombined(reason, keyset, masterKey, result)
        } else {
            rebindDeviceCredential(
                reason = reason,
                keyset = keyset,
                masterKey = masterKey,
                strongBiometricAvailable =
                    capabilities.strongBiometricAvailable,
                result = result,
            )
        }
    }

    private fun rebindCombined(
        reason: String,
        keyset: SecurityKeyset,
        masterKey: ByteArray,
        result: NativeResult<Unit>,
    ) {
        val kind = EnvelopeKind.COMBINED
        val alias = KeyringCrypto.alias(keyset.keyId, kind)
        val handle = createRequired(
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
                reason = reason,
                mode = SystemAuthenticatorMode.COMBINED,
                cipher = preparedCipher,
                operationId = result.operationId(),
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
        ) { authenticatedCipher ->
            val envelope = KeyringCrypto.wrap(
                keyId = keyset.keyId,
                kind = kind,
                alias = alias,
                securityLevel = handle.securityLevel,
                cipher = authenticatedCipher ?: preparedCipher,
                masterKey = masterKey,
            )
            completeSuccess(
                keyset = keyset,
                masterKey = masterKey,
                envelopes = listOf(envelope),
                result = result,
            )
        }
    }

    private fun rebindDeviceCredential(
        reason: String,
        keyset: SecurityKeyset,
        masterKey: ByteArray,
        strongBiometricAvailable: Boolean,
        result: NativeResult<Unit>,
    ) {
        val kind = EnvelopeKind.DEVICE_CREDENTIAL
        val alias = KeyringCrypto.alias(keyset.keyId, kind)
        val handle = createRequired(
            alias,
            WrappingKeyPolicy.DEVICE_CREDENTIAL_WINDOW,
            masterKey,
            result,
        ) ?: return
        authenticateRequired(
            request = SystemAuthRequest(
                reason = reason,
                mode = SystemAuthenticatorMode.DEVICE_CREDENTIAL,
                operationId = result.operationId(),
            ),
            alias = alias,
            masterKey = masterKey,
            result = result,
        ) {
            val deviceEnvelope = KeyringCrypto.wrap(
                keyId = keyset.keyId,
                kind = kind,
                alias = alias,
                securityLevel = handle.securityLevel,
                cipher = handle.encryptionCipher(),
                masterKey = masterKey,
            )
            if (strongBiometricAvailable) {
                rebindOptionalBiometric(
                    reason,
                    keyset,
                    masterKey,
                    deviceEnvelope,
                    result,
                )
            } else {
                completeSuccess(
                    keyset,
                    masterKey,
                    listOf(deviceEnvelope),
                    result,
                )
            }
        }
    }

    private fun rebindOptionalBiometric(
        reason: String,
        keyset: SecurityKeyset,
        masterKey: ByteArray,
        deviceEnvelope: SecurityEnvelope,
        result: NativeResult<Unit>,
    ) {
        val kind = EnvelopeKind.BIOMETRIC
        val alias = KeyringCrypto.alias(keyset.keyId, kind)
        val handle = try {
            wrappingKeys.create(
                alias,
                WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE,
            )
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(
                keyset,
                masterKey,
                listOf(deviceEnvelope),
                result,
            )
            return
        }
        val preparedCipher = try {
            handle.encryptionCipher()
        } catch (_: Throwable) {
            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
            completeSuccess(
                keyset,
                masterKey,
                listOf(deviceEnvelope),
                result,
            )
            return
        }
        try {
            authenticator.authenticate(
                SystemAuthRequest(
                    reason = reason,
                    mode = SystemAuthenticatorMode.BIOMETRIC,
                    cipher = preparedCipher,
                    operationId = result.operationId(),
                ),
                object : AuthenticationTerminal {
                    override fun succeeded(cipher: Cipher?) {
                        result.runIfActive {
                            val biometricEnvelope = try {
                                KeyringCrypto.wrap(
                                    keyId = keyset.keyId,
                                    kind = kind,
                                    alias = alias,
                                    securityLevel = handle.securityLevel,
                                    cipher = cipher ?: preparedCipher,
                                    masterKey = masterKey,
                                )
                            } catch (_: Throwable) {
                                KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                                completeSuccess(
                                    keyset,
                                    masterKey,
                                    listOf(deviceEnvelope),
                                    result,
                                )
                                return@runIfActive
                            }
                            completeSuccess(
                                keyset = keyset,
                                masterKey = masterKey,
                                envelopes =
                                    listOf(deviceEnvelope, biometricEnvelope),
                                result = result,
                                fallbackEnvelopes = listOf(deviceEnvelope),
                            )
                        }
                    }

                    override fun failed(error: NativeSecurityException) {
                        result.runIfActive {
                            KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                            completeSuccess(
                                keyset,
                                masterKey,
                                listOf(deviceEnvelope),
                                result,
                            )
                        }
                    }
                },
            )
        } catch (_: Throwable) {
            result.runIfActive {
                KeyringCrypto.cleanupAlias(wrappingKeys, alias)
                completeSuccess(
                    keyset,
                    masterKey,
                    listOf(deviceEnvelope),
                    result,
                )
            }
        }
    }

    private fun createRequired(
        alias: String,
        policy: WrappingKeyPolicy,
        masterKey: ByteArray,
        result: NativeResult<Unit>,
    ): WrappingKeyHandle? {
        return try {
            wrappingKeys.create(alias, policy)
        } catch (error: Throwable) {
            failRequired(alias, masterKey, result, error)
            null
        }
    }

    private fun authenticateRequired(
        request: SystemAuthRequest,
        alias: String,
        masterKey: ByteArray,
        result: NativeResult<Unit>,
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
                                failRequired(
                                    alias,
                                    masterKey,
                                    result,
                                    error,
                                )
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
        result: NativeResult<Unit>,
        error: Throwable,
    ) {
        KeyringCrypto.cleanupAlias(wrappingKeys, alias)
        masterKey.fill(0)
        result.error(KeyringCrypto.mapKeyError(error))
    }

    private fun completeSuccess(
        keyset: SecurityKeyset,
        masterKey: ByteArray,
        envelopes: List<SecurityEnvelope>,
        result: NativeResult<Unit>,
        fallbackEnvelopes: List<SecurityEnvelope>? = null,
    ) {
        try {
            val rebound = keyset.copy(
                envelopes = envelopes,
                pinResetRequired = false,
            )
            result.runIfActive {
                try {
                    envelopeStore.write(SecurityKeysetCodec.encode(rebound))
                } catch (error: Throwable) {
                    val fallback = fallbackEnvelopes ?: throw error
                    val retainedAliases =
                        fallback.mapTo(mutableSetOf()) { it.keyAlias }
                    envelopes.filterNot { it.keyAlias in retainedAliases }
                        .forEach {
                            KeyringCrypto.cleanupAlias(
                                wrappingKeys,
                                it.keyAlias,
                            )
                        }
                    envelopeStore.write(
                        SecurityKeysetCodec.encode(
                            keyset.copy(
                                envelopes = fallback,
                                pinResetRequired = false,
                            ),
                        ),
                    )
                }
                result.success(Unit)
            }
        } catch (error: Throwable) {
            envelopes.forEach {
                KeyringCrypto.cleanupAlias(wrappingKeys, it.keyAlias)
            }
            result.error(KeyringCrypto.mapKeyError(error))
        } finally {
            masterKey.fill(0)
        }
    }

    private fun expectedAliases(
        keyId: String,
        capabilities: SystemAuthCapabilities,
    ): List<String> {
        return if (apiLevel >= 30) {
            listOf(KeyringCrypto.alias(keyId, EnvelopeKind.COMBINED))
        } else {
            buildList {
                add(
                    KeyringCrypto.alias(
                        keyId,
                        EnvelopeKind.DEVICE_CREDENTIAL,
                    ),
                )
                if (capabilities.strongBiometricAvailable) {
                    add(KeyringCrypto.alias(keyId, EnvelopeKind.BIOMETRIC))
                }
            }
        }
    }
}
