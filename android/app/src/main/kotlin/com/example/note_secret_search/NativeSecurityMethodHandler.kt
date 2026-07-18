package com.example.note_secret_search

import com.example.note_secret_search.security.NativeKeyringOperations
import com.example.note_secret_search.security.NativeSecurityErrorCode
import com.example.note_secret_search.security.NativeSecurityException
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal class NativeSecurityMethodHandler(
    private val operations: NativeKeyringOperations,
) {
    fun getSecurityState(result: MethodChannel.Result) {
        handle(result) {
            operations.getSecurityState().toChannelMap()
        }
    }

    fun provisionWithSystemAuth(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.provisionWithSystemAuth(it, channelResult(result))
        }
    }

    fun unlockWithSystemAuth(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.unlockWithSystemAuth(it, channelResult(result))
        }
    }

    fun configurePin(
        reason: Any?,
        pin: Any?,
        result: MethodChannel.Result,
    ) {
        val ownedPin = pinBytes(pin, result) ?: return
        withReason(
            value = reason,
            result = result,
            rejected = { ownedPin.fill(0) },
        ) {
            operations.configurePin(it, ownedPin, unitChannelResult(result))
        }
    }

    fun unlockWithPin(
        pin: Any?,
        result: MethodChannel.Result,
    ) {
        val ownedPin = pinBytes(pin, result) ?: return
        try {
            operations.unlockWithPin(ownedPin, channelResult(result))
        } catch (error: Throwable) {
            ownedPin.fill(0)
            sendError(result, sanitizeSecurityError(error))
        }
    }

    fun rebindSystemAuthWithPin(
        reason: Any?,
        pin: Any?,
        result: MethodChannel.Result,
    ) {
        val ownedPin = pinBytes(pin, result) ?: return
        withReason(
            value = reason,
            result = result,
            rejected = { ownedPin.fill(0) },
        ) {
            operations.rebindSystemAuthWithPin(
                it,
                ownedPin,
                unitChannelResult(result),
            )
        }
    }

    fun removePin(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.removePin(it, unitChannelResult(result))
        }
    }

    fun beginLegacyMigration(
        reason: Any?,
        result: MethodChannel.Result,
    ) {
        withReason(reason, result) {
            operations.beginLegacyMigration(it, channelResult(result))
        }
    }

    fun getLegacyMigrationState(result: MethodChannel.Result) {
        handle(result, operations::getLegacyMigrationState)
    }

    fun prepareLegacyMigrationBackup(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::prepareLegacyMigrationBackup)
    }

    fun prepareLegacyMigrationPending(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::prepareLegacyMigrationPending)
    }

    fun markLegacyMigrationRowsCopied(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::markLegacyMigrationRowsCopied)
    }

    fun markLegacyMigrationValidated(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::markLegacyMigrationValidated)
    }

    fun activateLegacyMigration(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::activateLegacyMigration)
    }

    fun markLegacyMigrationPostSwapValidated(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(
            keyId,
            result,
            operations::markLegacyMigrationPostSwapValidated,
        )
    }

    fun cleanupLegacyMigrationFiles(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result, operations::cleanupLegacyMigrationFiles)
    }

    fun finishLegacyMigration(
        keyId: Any?,
        result: MethodChannel.Result,
    ) {
        withKeyId(keyId, result) {
            operations.finishLegacyMigration(it)
            null
        }
    }

    fun commitLegacyMigration(
        keyId: Any?,
        activeDigest: Any?,
        result: MethodChannel.Result,
    ) {
        val normalizedKeyId = canonicalKeyId(keyId)
        val normalizedDigest = activeDigest as? String
        if (
            normalizedKeyId == null ||
            normalizedDigest == null ||
            !MIGRATION_DIGEST_PATTERN.matches(normalizedDigest)
        ) {
            sendError(
                result,
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        try {
            operations.commitLegacyMigration(
                normalizedKeyId,
                normalizedDigest,
                unitChannelResult(result),
            )
        } catch (error: Throwable) {
            sendError(result, sanitizeSecurityError(error))
        }
    }

    fun abortLegacyMigration(result: MethodChannel.Result) {
        try {
            operations.abortLegacyMigration(unitChannelResult(result))
        } catch (error: Throwable) {
            sendError(result, sanitizeSecurityError(error))
        }
    }

    fun lock(result: MethodChannel.Result) {
        handle(result) {
            operations.lock()
        }
    }

    private fun withReason(
        value: Any?,
        result: MethodChannel.Result,
        rejected: () -> Unit = {},
        operation: (String) -> Unit,
    ) {
        val reason = value as? String
        if (reason.isNullOrBlank()) {
            rejected()
            sendError(
                result,
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        try {
            operation(reason)
        } catch (error: Throwable) {
            rejected()
            sendError(result, sanitizeSecurityError(error))
        }
    }

    private fun withKeyId(
        value: Any?,
        result: MethodChannel.Result,
        operation: (String) -> Any?,
    ) {
        val keyId = canonicalKeyId(value)
        if (keyId == null) {
            sendError(
                result,
                NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
            )
            return
        }
        handle(result) { operation(keyId) }
    }

    private fun canonicalKeyId(value: Any?): String? {
        val keyId = value as? String ?: return null
        if (keyId.isBlank() || keyId != keyId.trim()) {
            return null
        }
        return try {
            keyId.takeIf { UUID.fromString(it).toString() == it }
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun pinBytes(
        value: Any?,
        result: MethodChannel.Result,
    ): ByteArray? {
        if (value is ByteArray) {
            return value
        }
        sendError(
            result,
            NativeSecurityException(NativeSecurityErrorCode.INVALID_ARGUMENT),
        )
        return null
    }

    private fun handle(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        try {
            result.success(operation())
        } catch (error: Throwable) {
            sendError(result, sanitizeSecurityError(error))
        }
    }

    private companion object {
        val MIGRATION_DIGEST_PATTERN = Regex("^[0-9a-f]{64}$")
    }
}
