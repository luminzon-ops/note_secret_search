package com.example.note_secret_search.security

enum class NativeSecurityErrorCode {
    INVALID_ARGUMENT,
    BUSY,
    SECURITY_NOT_PROVISIONED,
    DEVICE_CREDENTIAL_NOT_SET,
    AUTH_CANCELLED,
    AUTH_FAILED,
    AUTH_LOCKOUT,
    KEY_INVALIDATED,
    KEYSTORE_UNAVAILABLE,
    ENVELOPE_CORRUPT,
    MIGRATION_REQUIRED,
    RECOVERY_REQUIRED,
    SECURE_STORAGE_UNAVAILABLE,
    INTERNAL_ERROR,
}

class NativeSecurityException(
    val code: NativeSecurityErrorCode,
    cause: Throwable? = null,
) : RuntimeException(publicMessage(code), cause) {
    companion object {
        fun publicMessage(code: NativeSecurityErrorCode): String {
            return when (code) {
                NativeSecurityErrorCode.INVALID_ARGUMENT -> "Invalid security request."
                NativeSecurityErrorCode.BUSY -> "A security operation is already active."
                NativeSecurityErrorCode.SECURITY_NOT_PROVISIONED -> "Security is not provisioned."
                NativeSecurityErrorCode.DEVICE_CREDENTIAL_NOT_SET ->
                    "A secure device credential is required."
                NativeSecurityErrorCode.AUTH_CANCELLED -> "Authentication was cancelled."
                NativeSecurityErrorCode.AUTH_FAILED -> "Authentication failed."
                NativeSecurityErrorCode.AUTH_LOCKOUT -> "Authentication is temporarily locked."
                NativeSecurityErrorCode.KEY_INVALIDATED -> "The protected key was invalidated."
                NativeSecurityErrorCode.KEYSTORE_UNAVAILABLE ->
                    "The Android Keystore is unavailable."
                NativeSecurityErrorCode.ENVELOPE_CORRUPT -> "The security envelope is corrupt."
                NativeSecurityErrorCode.MIGRATION_REQUIRED -> "Security migration is required."
                NativeSecurityErrorCode.RECOVERY_REQUIRED -> "Security recovery is required."
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE ->
                    "Secure storage is unavailable."
                NativeSecurityErrorCode.INTERNAL_ERROR -> "An internal security error occurred."
            }
        }
    }
}

enum class SecurityStatus(val channelValue: String) {
    UNPROVISIONED("unprovisioned"),
    LEGACY_MIGRATION_REQUIRED("legacyMigrationRequired"),
    LOCKED("locked"),
    RECOVERY_REQUIRED("recoveryRequired"),
}

enum class KeySecurityLevel(val channelValue: String) {
    STRONG_BOX("strongBox"),
    TEE("tee"),
    SOFTWARE("software"),
    UNKNOWN("unknown");

    companion object {
        fun fromChannelValue(value: String): KeySecurityLevel {
            return entries.firstOrNull { it.channelValue == value }
                ?: throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT)
        }
    }
}

data class NativeSecurityState(
    val status: SecurityStatus,
    val keyId: String? = null,
    val deviceCredentialAvailable: Boolean,
    val strongBiometricAvailable: Boolean,
    val securityLevel: KeySecurityLevel,
) {
    fun toChannelMap(): Map<String, Any> {
        return buildMap {
            put("status", status.channelValue)
            keyId?.let { put("keyId", it) }
            put("pinConfigured", false)
            put("deviceCredentialAvailable", deviceCredentialAvailable)
            put("strongBiometricAvailable", strongBiometricAvailable)
            put("securityLevel", securityLevel.channelValue)
        }
    }
}

data class NativeUnlockMaterial(
    val keyId: String,
    val databaseKey: ByteArray,
    val fieldKey: ByteArray,
    val unlockMethod: String = "system",
) {
    fun toChannelMap(): Map<String, Any> {
        return mapOf(
            "keyId" to keyId,
            "databaseKey" to databaseKey,
            "fieldKey" to fieldKey,
            "unlockMethod" to unlockMethod,
        )
    }

    fun zeroize() {
        databaseKey.fill(0)
        fieldKey.fill(0)
    }
}

enum class EnvelopeKind(val serializedName: String) {
    COMBINED("combined"),
    DEVICE_CREDENTIAL("deviceCredential"),
    BIOMETRIC("biometric");

    companion object {
        fun fromSerializedName(value: String): EnvelopeKind {
            return entries.firstOrNull { it.serializedName == value }
                ?: throw NativeSecurityException(NativeSecurityErrorCode.ENVELOPE_CORRUPT)
        }
    }
}

class SecurityEnvelope(
    val kind: EnvelopeKind,
    val keyAlias: String,
    val nonce: ByteArray,
    val ciphertext: ByteArray,
    val tag: ByteArray,
    val securityLevel: KeySecurityLevel,
) {
    fun copy(
        kind: EnvelopeKind = this.kind,
        keyAlias: String = this.keyAlias,
        nonce: ByteArray = this.nonce,
        ciphertext: ByteArray = this.ciphertext,
        tag: ByteArray = this.tag,
        securityLevel: KeySecurityLevel = this.securityLevel,
    ): SecurityEnvelope {
        return SecurityEnvelope(kind, keyAlias, nonce, ciphertext, tag, securityLevel)
    }

    override fun equals(other: Any?): Boolean {
        return other is SecurityEnvelope &&
            kind == other.kind &&
            keyAlias == other.keyAlias &&
            nonce.contentEquals(other.nonce) &&
            ciphertext.contentEquals(other.ciphertext) &&
            tag.contentEquals(other.tag) &&
            securityLevel == other.securityLevel
    }

    override fun hashCode(): Int {
        var result = kind.hashCode()
        result = 31 * result + keyAlias.hashCode()
        result = 31 * result + nonce.contentHashCode()
        result = 31 * result + ciphertext.contentHashCode()
        result = 31 * result + tag.contentHashCode()
        result = 31 * result + securityLevel.hashCode()
        return result
    }
}

data class SecurityKeyset(
    val keyId: String,
    val envelopes: List<SecurityEnvelope>,
)

data class SystemAuthCapabilities(
    val deviceCredentialAvailable: Boolean,
    val strongBiometricAvailable: Boolean,
)

interface NativeResult<T> {
    fun success(value: T)

    fun error(error: NativeSecurityException)
}
