package com.example.note_secret_search

import com.example.note_secret_search.security.KeySecurityLevel
import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeResult
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
import com.example.note_secret_search.security.NativeSecurityState
import com.example.note_secret_search.security.NativeUnlockMaterial
import com.example.note_secret_search.security.SecurityStatus
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
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
                "systemRebindRequired" to false,
                "pinResetRequired" to false,
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
        assertArrayEquals(
            ByteArray(32) { 3 },
            map["searchIndexFingerprintKey"] as ByteArray,
        )
        assertEquals("system", map["unlockMethod"])
        assertEquals("Unlock", operations.lastReason)
        assertTrue(operations.lastMaterial!!.databaseKey.all { it == 0.toByte() })
        assertTrue(operations.lastMaterial!!.fieldKey.all { it == 0.toByte() })
        assertTrue(
            operations.lastMaterial!!.searchIndexFingerprintKey!!.all {
                it == 0.toByte()
            },
        )
    }

    @Test
    fun `configure pin forwards owned bytes and returns void`() {
        val result = RecordingMethodResult()
        val pin = "2468".toByteArray()

        handler.configurePin("Configure fallback PIN", pin, result)

        assertEquals("Configure fallback PIN", operations.lastReason)
        assertArrayEquals("2468".toByteArray(), operations.lastPin)
        assertTrue(pin.all { it == 0.toByte() })
        assertEquals(1, result.successCalls)
        assertNull(result.value)
    }

    @Test
    fun `pin unlock returns byte arrays and pin unlock method`() {
        val result = CopyingMethodResult()
        val pin = "2468".toByteArray()

        handler.unlockWithPin(pin, result)

        val map = result.value as Map<*, *>
        assertEquals("pin", map["unlockMethod"])
        assertArrayEquals("2468".toByteArray(), operations.lastPin)
        assertTrue(pin.all { it == 0.toByte() })
        assertTrue(operations.lastMaterial!!.databaseKey.all { it == 0.toByte() })
        assertTrue(operations.lastMaterial!!.fieldKey.all { it == 0.toByte() })
        assertTrue(
            operations.lastMaterial!!.searchIndexFingerprintKey!!.all {
                it == 0.toByte()
            },
        )
    }

    @Test
    fun `system rebind forwards owned pin bytes and returns void`() {
        val result = RecordingMethodResult()
        val pin = "2468".toByteArray()

        handler.rebindSystemAuthWithPin(
            "Restore system authentication",
            pin,
            result,
        )

        assertEquals("Restore system authentication", operations.lastReason)
        assertArrayEquals("2468".toByteArray(), operations.lastPin)
        assertTrue(pin.all { it == 0.toByte() })
        assertEquals(1, result.successCalls)
        assertNull(result.value)
    }

    @Test
    fun `remove pin forwards reason and returns void`() {
        val result = RecordingMethodResult()

        handler.removePin("Remove fallback PIN", result)

        assertEquals("Remove fallback PIN", operations.lastReason)
        assertEquals(1, result.successCalls)
        assertNull(result.value)
    }

    @Test
    fun `migration begin returns keys and clears native material`() {
        val result = CopyingMethodResult()

        handler.beginLegacyMigration("Upgrade security", result)

        val map = result.value as Map<*, *>
        assertEquals("Upgrade security", operations.lastReason)
        assertArrayEquals(ByteArray(32) { 1 }, map["databaseKey"] as ByteArray)
        assertArrayEquals(ByteArray(32) { 2 }, map["fieldKey"] as ByteArray)
        assertArrayEquals(
            ByteArray(32) { 3 },
            map["searchIndexFingerprintKey"] as ByteArray,
        )
        assertTrue(operations.lastMaterial!!.databaseKey.all { it == 0.toByte() })
        assertTrue(operations.lastMaterial!!.fieldKey.all { it == 0.toByte() })
        assertTrue(
            operations.lastMaterial!!.searchIndexFingerprintKey!!.all {
                it == 0.toByte()
            },
        )
    }

    @Test
    fun `migration commit and abort return void`() {
        val commit = RecordingMethodResult()
        val abort = RecordingMethodResult()

        handler.commitLegacyMigration(
            "123e4567-e89b-12d3-a456-426614174000",
            "a".repeat(64),
            commit,
        )
        handler.abortLegacyMigration(abort)

        assertEquals(1, commit.successCalls)
        assertEquals(1, abort.successCalls)
        assertNull(commit.value)
        assertNull(abort.value)
    }

    @Test
    fun `migration methods reject a non canonical key id`() {
        val result = RecordingMethodResult()

        handler.prepareLegacyMigrationPending("key-v2", result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertEquals(0, operations.migrationCalls)
    }

    @Test
    fun `migration commit rejects a non sha256 digest`() {
        val result = RecordingMethodResult()

        handler.commitLegacyMigration(
            "123e4567-e89b-12d3-a456-426614174000",
            "active-digest",
            result,
        )

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertEquals(0, operations.migrationCalls)
    }

    @Test
    fun `invalid configure reason clears supplied pin`() {
        val result = RecordingMethodResult()
        val pin = "2468".toByteArray()

        handler.configurePin(" ", pin, result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertTrue(pin.all { it == 0.toByte() })
        assertNull(operations.lastPin)
    }

    @Test
    fun `non byte pin payload maps to invalid argument`() {
        val result = RecordingMethodResult()

        handler.unlockWithPin("2468", result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertNull(operations.lastPin)
    }

    @Test
    fun `invalid reason maps to stable invalid argument error`() {
        val result = RecordingMethodResult()

        handler.provisionWithSystemAuth(7, result)

        assertEquals("INVALID_ARGUMENT", result.errorCode)
        assertNull(operations.lastReason)
    }

    @Test
    fun `recent task protection rejects malformed obscured values`() {
        for (value in listOf(null, "false", 0)) {
            val error = assertThrows(NativeSecurityException::class.java) {
                requireRecentTaskObscured(value)
            }

            assertEquals(NativeSecurityErrorCode.INVALID_ARGUMENT, error.code)
        }
        assertTrue(requireRecentTaskObscured(true))
        assertEquals(false, requireRecentTaskObscured(false))
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
    var lastPin: ByteArray? = null
    var migrationCalls = 0

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

    override fun configurePin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        lastReason = reason
        lastPin = pin.clone()
        pin.fill(0)
        result.success(Unit)
    }

    override fun unlockWithPin(
        pin: ByteArray,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        lastPin = pin.clone()
        pin.fill(0)
        result.success(material().copy(unlockMethod = "pin"))
    }

    override fun rebindSystemAuthWithPin(
        reason: String,
        pin: ByteArray,
        result: NativeResult<Unit>,
    ) {
        lastReason = reason
        lastPin = pin.clone()
        pin.fill(0)
        result.success(Unit)
    }

    override fun removePin(
        reason: String,
        result: NativeResult<Unit>,
    ) {
        lastReason = reason
        result.success(Unit)
    }

    override fun beginLegacyMigration(
        reason: String,
        result: NativeResult<NativeUnlockMaterial>,
    ) {
        lastReason = reason
        result.success(material())
    }

    override fun getLegacyMigrationState(): Map<String, Any?> = migrationState()

    override fun prepareLegacyMigrationBackup(keyId: String): Map<String, Any?> {
        return migrationState()
    }

    override fun prepareLegacyMigrationPending(keyId: String): Map<String, Any?> {
        migrationCalls += 1
        return migrationState()
    }

    override fun markLegacyMigrationRowsCopied(keyId: String): Map<String, Any?> {
        return migrationState()
    }

    override fun markLegacyMigrationValidated(keyId: String): Map<String, Any?> {
        return migrationState()
    }

    override fun activateLegacyMigration(keyId: String): Map<String, Any?> {
        return migrationState()
    }

    override fun markLegacyMigrationPostSwapValidated(
        keyId: String,
    ): Map<String, Any?> = migrationState()

    override fun cleanupLegacyMigrationFiles(keyId: String): Map<String, Any?> {
        return migrationState()
    }

    override fun finishLegacyMigration(keyId: String) = Unit

    override fun commitLegacyMigration(
        keyId: String,
        activeDigest: String,
        result: NativeResult<Unit>,
    ) {
        migrationCalls += 1
        result.success(Unit)
    }

    override fun abortLegacyMigration(result: NativeResult<Unit>) {
        result.success(Unit)
    }

    override fun lock(): Any? = null

    private fun material(): NativeUnlockMaterial {
        return NativeUnlockMaterial(
            keyId = "123e4567-e89b-12d3-a456-426614174000",
            databaseKey = ByteArray(32) { 1 },
            fieldKey = ByteArray(32) { 2 },
            searchIndexFingerprintKey = ByteArray(32) { 3 },
        ).also { lastMaterial = it }
    }

    private fun migrationState(): Map<String, Any?> {
        return mapOf(
            "stage" to "detected",
            "sourcePath" to "/fixed/backup.db",
            "pendingPath" to "/fixed/pending.db",
            "activePath" to "/fixed/active.db",
        )
    }
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
    var successCalls = 0

    override fun success(result: Any?) {
        successCalls += 1
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
            "searchIndexFingerprintKey" to
                (map["searchIndexFingerprintKey"] as ByteArray).clone(),
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
