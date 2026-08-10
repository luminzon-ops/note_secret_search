package com.example.note_secret_search.security

import java.util.UUID
import org.json.JSONObject

enum class MigrationJournalStage(val serializedName: String) {
    DETECTED("detected"),
    KEYRING_READY("keyringReady"),
    BACKUP_READY("backupReady"),
    PENDING_CREATED("pendingCreated"),
    ROWS_COPIED("rowsCopied"),
    VALIDATED("validated"),
    OLD_MOVED("oldMoved"),
    NEW_ACTIVATED("newActivated"),
    POST_SWAP_VALIDATED("postSwapValidated"),
    CLEANUP_COMPLETE("cleanupComplete");

    companion object {
        fun fromSerializedName(value: String): MigrationJournalStage {
            return entries.firstOrNull { it.serializedName == value }
                ?: migrationFailure()
        }
    }
}

data class MigrationJournal(
    val stage: MigrationJournalStage,
    val keyId: String? = null,
    val sourceDigest: String? = null,
    val pendingDigest: String? = null,
    val activeDigest: String? = null,
) {
    fun toChannelMap(paths: MigrationFileSetAccess): Map<String, Any?> {
        return mapOf(
            "stage" to stage.serializedName,
            "keyId" to keyId,
            "sourcePath" to paths.path(MigrationFileSlot.BACKUP),
            "pendingPath" to paths.path(MigrationFileSlot.PENDING),
            "activePath" to paths.path(MigrationFileSlot.ACTIVE),
            "sourceDigest" to sourceDigest,
            "pendingDigest" to pendingDigest,
            "activeDigest" to activeDigest,
        )
    }
}

interface MigrationJournalStore {
    fun read(): MigrationJournal?

    fun write(value: MigrationJournal)

    fun delete()
}

object MigrationJournalCodec {
    private const val VERSION = 1
    private val exactKeys = setOf(
        "version",
        "stage",
        "keyId",
        "sourceDigest",
        "pendingDigest",
        "activeDigest",
    )
    private val digestPattern = Regex("^[0-9a-f]{64}$")

    fun encode(value: MigrationJournal): ByteArray {
        validate(value)
        return JSONObject()
            .put("version", VERSION)
            .put("stage", value.stage.serializedName)
            .put("keyId", value.keyId ?: JSONObject.NULL)
            .put("sourceDigest", value.sourceDigest ?: JSONObject.NULL)
            .put("pendingDigest", value.pendingDigest ?: JSONObject.NULL)
            .put("activeDigest", value.activeDigest ?: JSONObject.NULL)
            .toString()
            .toByteArray(Charsets.UTF_8)
    }

    fun decode(value: ByteArray): MigrationJournal {
        return try {
            if (value.isEmpty() || value.size > 64 * 1024) {
                migrationFailure()
            }
            val root = JSONObject(value.toString(Charsets.UTF_8))
            val actualKeys = mutableSetOf<String>()
            root.keys().forEachRemaining(actualKeys::add)
            if (actualKeys != exactKeys || root.getInt("version") != VERSION) {
                migrationFailure()
            }
            MigrationJournal(
                stage = MigrationJournalStage.fromSerializedName(
                    root.getString("stage"),
                ),
                keyId = root.nullableString("keyId"),
                sourceDigest = root.nullableString("sourceDigest"),
                pendingDigest = root.nullableString("pendingDigest"),
                activeDigest = root.nullableString("activeDigest"),
            ).also(::validate)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_FAILED,
                error,
            )
        }
    }

    private fun validate(value: MigrationJournal) {
        val stage = value.stage
        if (stage >= MigrationJournalStage.KEYRING_READY) {
            val keyId = value.keyId ?: migrationFailure()
            try {
                if (UUID.fromString(keyId).toString() != keyId) {
                    migrationFailure()
                }
            } catch (error: IllegalArgumentException) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.MIGRATION_FAILED,
                    error,
                )
            }
        } else if (value.keyId != null) {
            migrationFailure()
        }
        if (stage >= MigrationJournalStage.BACKUP_READY) {
            requireDigest(value.sourceDigest)
        } else if (value.sourceDigest != null) {
            migrationFailure()
        }
        if (stage >= MigrationJournalStage.VALIDATED) {
            requireDigest(value.pendingDigest)
        } else if (value.pendingDigest != null) {
            migrationFailure()
        }
        if (stage >= MigrationJournalStage.POST_SWAP_VALIDATED) {
            requireDigest(value.activeDigest)
        } else if (value.activeDigest != null) {
            migrationFailure()
        }
    }

    private fun requireDigest(value: String?) {
        if (value == null || !digestPattern.matches(value)) {
            migrationFailure()
        }
    }

    private fun JSONObject.nullableString(name: String): String? {
        return if (isNull(name)) null else getString(name)
    }
}

internal fun migrationFailure(): Nothing {
    throw NativeSecurityException(NativeSecurityErrorCode.MIGRATION_FAILED)
}
