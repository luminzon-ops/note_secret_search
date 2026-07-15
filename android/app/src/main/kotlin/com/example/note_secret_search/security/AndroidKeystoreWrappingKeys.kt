package com.example.note_secret_search.security

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.InvalidAlgorithmParameterException
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

class AndroidKeystoreWrappingKeyBackend(
    private val apiLevel: Int = Build.VERSION.SDK_INT,
) : WrappingKeyBackend {
    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
        requestStrongBox: Boolean,
    ): WrappingKeyHandle {
        try {
            val generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE,
            )
            generator.init(buildSpec(alias, policy, requestStrongBox))
            val key = generator.generateKey()
            val level = securityLevel(key, requestStrongBox)
            return AndroidWrappingKeyHandle(alias, level, key)
        } catch (error: StrongBoxUnavailableException) {
            throw StrongBoxUnavailableFailure(error)
        } catch (error: InvalidAlgorithmParameterException) {
            if (requestStrongBox) {
                throw StrongBoxUnsupportedFailure(error)
            }
            throw KeystoreOperationFailure(error)
        } catch (error: ProviderException) {
            throw KeystoreOperationFailure(error)
        } catch (error: Exception) {
            throw KeystoreOperationFailure(error)
        }
    }

    override fun load(alias: String): WrappingKeyHandle? {
        return try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val key = keyStore.getKey(alias, null) as? SecretKey ?: return null
            AndroidWrappingKeyHandle(alias, securityLevel(key, false), key)
        } catch (error: Exception) {
            throw KeystoreOperationFailure(error)
        }
    }

    override fun delete(alias: String) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(alias)) {
                keyStore.deleteEntry(alias)
            }
        } catch (error: Exception) {
            throw KeystoreOperationFailure(error)
        }
    }

    private fun buildSpec(
        alias: String,
        policy: WrappingKeyPolicy,
        requestStrongBox: Boolean,
    ): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)

        if (apiLevel >= 30) {
            val authTypes = when (policy) {
                WrappingKeyPolicy.COMBINED_AUTH_PER_USE ->
                    KeyProperties.AUTH_BIOMETRIC_STRONG or
                        KeyProperties.AUTH_DEVICE_CREDENTIAL
                WrappingKeyPolicy.DEVICE_CREDENTIAL_WINDOW ->
                    KeyProperties.AUTH_DEVICE_CREDENTIAL
                WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE ->
                    KeyProperties.AUTH_BIOMETRIC_STRONG
            }
            builder.setUserAuthenticationParameters(0, authTypes)
        } else {
            val durationSeconds = if (
                policy == WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE
            ) {
                -1
            } else {
                DEVICE_CREDENTIAL_WINDOW_SECONDS
            }
            builder.setUserAuthenticationValidityDurationSeconds(durationSeconds)
            if (policy == WrappingKeyPolicy.BIOMETRIC_AUTH_PER_USE) {
                builder.setInvalidatedByBiometricEnrollment(true)
            }
        }
        if (requestStrongBox && apiLevel >= 28) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    private fun securityLevel(
        key: SecretKey,
        requestedStrongBox: Boolean,
    ): KeySecurityLevel {
        if (requestedStrongBox && apiLevel in 28..30) {
            return KeySecurityLevel.STRONG_BOX
        }
        return try {
            val factory = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            val keyInfo = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            if (apiLevel >= 31) {
                when (keyInfo.securityLevel) {
                    KeyProperties.SECURITY_LEVEL_STRONGBOX -> KeySecurityLevel.STRONG_BOX
                    KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> KeySecurityLevel.TEE
                    KeyProperties.SECURITY_LEVEL_SOFTWARE -> KeySecurityLevel.SOFTWARE
                    else -> KeySecurityLevel.UNKNOWN
                }
            } else if (keyInfo.isInsideSecureHardware) {
                KeySecurityLevel.TEE
            } else {
                KeySecurityLevel.SOFTWARE
            }
        } catch (_: Exception) {
            KeySecurityLevel.UNKNOWN
        }
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val DEVICE_CREDENTIAL_WINDOW_SECONDS = 30
    }
}

private class AndroidWrappingKeyHandle(
    override val alias: String,
    override val securityLevel: KeySecurityLevel,
    private val key: SecretKey,
) : WrappingKeyHandle {
    override fun encryptionCipher(): Cipher {
        return cipher(Cipher.ENCRYPT_MODE, null)
    }

    override fun decryptionCipher(nonce: ByteArray): Cipher {
        return cipher(Cipher.DECRYPT_MODE, nonce)
    }

    private fun cipher(mode: Int, nonce: ByteArray?): Cipher {
        return try {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                if (nonce == null) {
                    init(mode, key)
                } else {
                    init(mode, key, GCMParameterSpec(128, nonce))
                }
            }
        } catch (error: KeyPermanentlyInvalidatedException) {
            throw WrappingKeyInvalidatedException(error)
        } catch (error: Exception) {
            throw KeystoreOperationFailure(error)
        }
    }
}
