package com.example.note_secret_search

import com.example.note_secret_search.security.KeySecurityLevel
import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityState
import com.example.note_secret_search.security.NativeUnlockMaterial
import com.example.note_secret_search.security.SecurityStatus
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityKeyNativeMethodHandlerTest {
    private val operations = RecordingNativeKeyringOperations()
    private val handler = NativeSecurityMethodHandler(operations)

    @Test
    fun `get security state returns the exact channel map`() {
        val result = RecordingMethodResult()

        handler.getSecurityState(result)

        assertEquals(
            mapOf(
                "status" to "locked",
                "keyId" to "123e4567-e89b-12d3-a456-426614174000",
                "pinConfigured" to false,
                "deviceCredentialAvailable" to true,
                "strongBiometricAvailable" to false,
                "securityLevel" to "tee",
            ),
            result.value,
        )
    }

    @Test
    fun `unlock returns byte arrays and system unlock method`() {
        val result = CopyingMethodResult()

        handler.unlockWithSystemAuth("Unlock", result)

        val map = result.value as Map<*, *>
        assertEquals("123e4567-e89b-12d3-a456-426614174000", map["keyId"])
        assertArrayEquals(ByteArray(32) { 1 }, map["databaseKey"] as ByteArray)
        assertArrayEquals(ByteArray(32) { 2 }, map["fieldKey"] as ByteArray)
        assertEquals("system", map["unlockMethod"])
        assertEquals("Unlock", operations.lastReason)
        assertTrue(operations.lastMaterial!!.databaseKey.all { it == 0.toByte() })
        assertTrue(operations.lastMaterial!!.fieldKey.all { it == 0.toByte() })
    }

    @Test
    fun `invalid reason maps to stable invalid argument error`() {
        val result = RecordingMethodResult()

        handler.provisionWithSystemAuth(7, result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertNull(operations.lastReason)
    }

    @Test
    fun `legacy key handlers preserve phase one success behavior`() {
        val legacy = RecordingLegacyKeyOperations()
        val legacyHandler = SecureKeyMethodHandler(legacy)
        val ensureResult = RecordingMethodResult()
        val materialResult = RecordingMethodResult()

        legacyHandler.ensureRootKey(ensureResult)
        legacyHandler.getDatabasePasswordMaterial(materialResult)

        assertEquals(1, legacy.ensureCalls)
        assertNull(ensureResult.value)
        assertEquals("legacy-material", materialResult.value)
    }

    @Test
    fun `legacy biometric handlers preserve availability and boolean authentication`() {
        val legacy = RecordingLegacyBiometricOperations()
        val legacyHandler = LegacyBiometricMethodHandler(legacy)
        val availability = RecordingMethodResult()
        val authentication = RecordingMethodResult()

        legacyHandler.getBiometricAvailability(availability)
        legacyHandler.authenticateWithBiometrics("Legacy unlock", authentication)

        assertEquals("available", availability.value)
        assertEquals(true, authentication.value)
        assertEquals("Legacy unlock", legacy.lastReason)
    }

    @Test
    fun `legacy biometric handler preserves the phase one default reason`() {
        val legacy = RecordingLegacyBiometricOperations()
        val legacyHandler = LegacyBiometricMethodHandler(legacy)

        legacyHandler.authenticateWithBiometrics(null, RecordingMethodResult())

        assertEquals("解锁保险库", legacy.lastReason)
    }
}

private class RecordingNativeKeyringOperations : NativeKeyringOperations {
    var lastReason: String? = null
    var lastMaterial: NativeUnlockMaterial? = null

    override fun getSecurityState(): NativeSecurityState {
        return NativeSecurityState(
            status = SecurityStatus.LOCKED,
            keyId = "123e4567-e89b-12d3-a456-426614174000",
            deviceCredentialAvailable = true,
            strongBiometricAvailable = false,
            securityLevel = KeySecurityLevel.TEE,
        )
    }

    override fun provisionWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        lastReason = reason
        result.success(material())
    }

    override fun unlockWithSystemAuth(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        lastReason = reason
        result.success(material())
    }

    override fun lock(): Any? = null

    private fun material(): NativeUnlockMaterial {
        return NativeUnlockMaterial(
            keyId = "123e4567-e89b-12d3-a456-426614174000",
            databaseKey = ByteArray(32) { 1 },
            fieldKey = ByteArray(32) { 2 },
        ).also { lastMaterial = it }
    }
}

private class RecordingLegacyKeyOperations : SecureKeyOperations {
    var ensureCalls = 0

    override fun ensureRootKey() {
        ensureCalls += 1
    }

    override fun getDatabasePasswordMaterial(): String = "legacy-material"
}

private class RecordingLegacyBiometricOperations : LegacyBiometricOperations {
    var lastReason: String? = null

    override fun getBiometricAvailability(): String = "available"

    override fun authenticateWithBiometrics(
        reason: String,
        result: MethodChannel.Result,
    ) {
        lastReason = reason
        result.success(true)
    }
}

private class RecordingMethodResult : MethodChannel.Result {
    var value: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
        value = result
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        this.errorCode = errorCode
    }

    override fun notImplemented() {
    }
}

private class CopyingMethodResult : MethodChannel.Result {
    var value: Any? = null

    override fun success(result: Any?) {
        val map = result as Map<*, *>
        value = mapOf(
            "keyId" to map["keyId"],
            "databaseKey" to (map["databaseKey"] as ByteArray).clone(),
            "fieldKey" to (map["fieldKey"] as ByteArray).clone(),
            "unlockMethod" to map["unlockMethod"],
        )
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
    }

    override fun notImplemented() {
    }
}
