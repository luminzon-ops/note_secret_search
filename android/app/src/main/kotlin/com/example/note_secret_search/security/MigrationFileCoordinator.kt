package com.example.note_secret_search.security

enum class MigrationFileSlot {
    ACTIVE,
    BACKUP,
    PENDING,
    ROLLBACK,
}

interface MigrationFileSetAccess {
    fun path(slot: MigrationFileSlot): String

    fun exists(slot: MigrationFileSlot): Boolean

    fun hasSidecars(slot: MigrationFileSlot): Boolean

    fun sizeBytes(slot: MigrationFileSlot): Long

    fun availableBytes(): Long

    fun digest(slot: MigrationFileSlot): String?

    fun copy(from: MigrationFileSlot, to: MigrationFileSlot)

    fun move(from: MigrationFileSlot, to: MigrationFileSlot)

    fun delete(slot: MigrationFileSlot)

    fun sync(slot: MigrationFileSlot)
}

internal fun MigrationFileCoordinator?.requireConfigured():
    MigrationFileCoordinator {
    return this ?: throw NativeSecurityException(
        NativeSecurityErrorCode.MIGRATION_FAILED,
    )
}

class MigrationFileCoordinator(
    private val files: MigrationFileSetAccess,
    private val journalStore: MigrationJournalStore,
) : MigrationCompletionVerifier {
    @Synchronized
    fun currentJournal(): MigrationJournal? = journalStore.read()

    @Synchronized
    fun hasActiveDatabase(): Boolean =
        files.exists(MigrationFileSlot.ACTIVE)

    @Synchronized
    fun isCredentialFinalizationReady(keyId: String): Boolean {
        val journal = currentJournal() ?: return false
        return journal.stage == MigrationJournalStage.CLEANUP_COMPLETE &&
            journal.keyId == keyId
    }

    @Synchronized
    fun inspectState(): Map<String, Any?> = stateMap(inspect())

    @Synchronized
    fun detect(): MigrationJournal {
        return journalStore.read() ?: run {
            if (!files.exists(MigrationFileSlot.ACTIVE)) {
                migrationFailure()
            }
            persist(MigrationJournal(MigrationJournalStage.DETECTED))
        }
    }

    @Synchronized
    fun inspect(): MigrationJournal {
        val journal = detect()
        return when (journal.stage) {
            MigrationJournalStage.VALIDATED ->
                resumeUnjournaledOldMove(journal)
            MigrationJournalStage.OLD_MOVED -> resumeOldMoved(journal)
            MigrationJournalStage.NEW_ACTIVATED -> verifyActivatedOrRestore(journal)
            else -> journal
        }
    }

    @Synchronized
    fun markKeyringReady(keyId: String): MigrationJournal {
        val journal = inspect()
        return when (journal.stage) {
            MigrationJournalStage.DETECTED -> persist(
                journal.copy(
                    stage = MigrationJournalStage.KEYRING_READY,
                    keyId = keyId,
                ),
            )
            else -> requireKey(journal, keyId)
        }
    }

    @Synchronized
    fun prepareBackupState(keyId: String): Map<String, Any?> {
        return stateMap(prepareBackup(keyId))
    }

    @Synchronized
    fun preparePendingState(keyId: String): Map<String, Any?> {
        return stateMap(preparePending(keyId))
    }

    @Synchronized
    fun markRowsCopiedState(keyId: String): Map<String, Any?> {
        return stateMap(markRowsCopied(keyId))
    }

    @Synchronized
    fun markValidatedState(keyId: String): Map<String, Any?> {
        return stateMap(markValidated(keyId))
    }

    @Synchronized
    fun activateState(keyId: String): Map<String, Any?> {
        return stateMap(activate(keyId))
    }

    @Synchronized
    fun markPostSwapValidatedState(keyId: String): Map<String, Any?> {
        return stateMap(markPostSwapValidated(keyId))
    }

    @Synchronized
    fun cleanupState(keyId: String): Map<String, Any?> {
        return stateMap(cleanup(keyId))
    }

    @Synchronized
    fun prepareBackup(keyId: String): MigrationJournal {
        val journal = requireKey(inspect(), keyId)
        if (journal.stage >= MigrationJournalStage.BACKUP_READY) {
            requireDigest(
                files.digest(MigrationFileSlot.BACKUP),
                journal.sourceDigest,
            )
            return journal
        }
        requireStage(journal, MigrationJournalStage.KEYRING_READY)
        requireMainOnly(MigrationFileSlot.ACTIVE)
        val sourceBytes = files.sizeBytes(MigrationFileSlot.ACTIVE)
        if (sourceBytes <= 0L) {
            migrationFailure()
        }
        val requiredBytes = try {
            Math.addExact(
                Math.multiplyExact(sourceBytes, 2L),
                MIGRATION_RESERVE_BYTES,
            )
        } catch (error: ArithmeticException) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_STORAGE_INSUFFICIENT,
                error,
            )
        }
        if (files.availableBytes() < requiredBytes) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_STORAGE_INSUFFICIENT,
            )
        }
        files.delete(MigrationFileSlot.BACKUP)
        files.copy(MigrationFileSlot.ACTIVE, MigrationFileSlot.BACKUP)
        files.sync(MigrationFileSlot.BACKUP)
        val sourceDigest = files.digest(MigrationFileSlot.ACTIVE)
            ?: migrationFailure()
        requireDigest(
            files.digest(MigrationFileSlot.BACKUP),
            sourceDigest,
        )
        return persist(
            journal.copy(
                stage = MigrationJournalStage.BACKUP_READY,
                sourceDigest = sourceDigest,
            ),
        )
    }

    @Synchronized
    fun preparePending(keyId: String): MigrationJournal {
        var journal = requireKey(inspect(), keyId)
        if (journal.stage == MigrationJournalStage.NEW_ACTIVATED) {
            journal = restoreRecovery(journal)
        }
        if (journal.stage >= MigrationJournalStage.VALIDATED) {
            return journal
        }
        if (
            journal.stage != MigrationJournalStage.BACKUP_READY &&
            journal.stage != MigrationJournalStage.PENDING_CREATED &&
            journal.stage != MigrationJournalStage.ROWS_COPIED
        ) {
            migrationFailure()
        }
        files.delete(MigrationFileSlot.PENDING)
        return persist(
            journal.copy(
                stage = MigrationJournalStage.PENDING_CREATED,
                pendingDigest = null,
                activeDigest = null,
            ),
        )
    }

    @Synchronized
    fun markRowsCopied(keyId: String): MigrationJournal {
        val journal = requireKey(inspect(), keyId)
        requireStage(journal, MigrationJournalStage.PENDING_CREATED)
        if (!files.exists(MigrationFileSlot.PENDING)) {
            migrationFailure()
        }
        requireMainOnly(MigrationFileSlot.PENDING)
        files.sync(MigrationFileSlot.PENDING)
        return persist(
            journal.copy(stage = MigrationJournalStage.ROWS_COPIED),
        )
    }

    @Synchronized
    fun markValidated(keyId: String): MigrationJournal {
        val journal = requireKey(inspect(), keyId)
        if (journal.stage >= MigrationJournalStage.VALIDATED) {
            return journal
        }
        requireStage(journal, MigrationJournalStage.ROWS_COPIED)
        val pendingDigest = files.digest(MigrationFileSlot.PENDING)
            ?: migrationFailure()
        return persist(
            journal.copy(
                stage = MigrationJournalStage.VALIDATED,
                pendingDigest = pendingDigest,
            ),
        )
    }

    @Synchronized
    fun activate(keyId: String): MigrationJournal {
        var journal = requireKey(inspect(), keyId)
        if (journal.stage >= MigrationJournalStage.NEW_ACTIVATED) {
            return journal
        }
        if (journal.stage == MigrationJournalStage.VALIDATED) {
            requireMainOnly(MigrationFileSlot.ACTIVE)
            requireMainOnly(MigrationFileSlot.PENDING)
            requireDigest(
                files.digest(MigrationFileSlot.PENDING),
                journal.pendingDigest,
            )
            files.delete(MigrationFileSlot.ROLLBACK)
            files.move(MigrationFileSlot.ACTIVE, MigrationFileSlot.ROLLBACK)
            files.sync(MigrationFileSlot.ROLLBACK)
            journal = persist(
                journal.copy(stage = MigrationJournalStage.OLD_MOVED),
            )
        }
        if (journal.stage == MigrationJournalStage.OLD_MOVED) {
            return resumeOldMoved(journal)
        }
        migrationFailure()
    }

    @Synchronized
    fun markPostSwapValidated(keyId: String): MigrationJournal {
        val journal = requireKey(inspect(), keyId)
        if (journal.stage >= MigrationJournalStage.POST_SWAP_VALIDATED) {
            return journal
        }
        requireStage(journal, MigrationJournalStage.NEW_ACTIVATED)
        val activeDigest = files.digest(MigrationFileSlot.ACTIVE)
            ?: migrationFailure()
        requireDigest(activeDigest, journal.pendingDigest)
        return persist(
            journal.copy(
                stage = MigrationJournalStage.POST_SWAP_VALIDATED,
                activeDigest = activeDigest,
            ),
        )
    }

    @Synchronized
    fun cleanup(keyId: String): MigrationJournal {
        val journal = requireKey(inspect(), keyId)
        if (journal.stage == MigrationJournalStage.CLEANUP_COMPLETE) {
            return journal
        }
        requireStage(journal, MigrationJournalStage.POST_SWAP_VALIDATED)
        if (
            files.hasSidecars(MigrationFileSlot.ACTIVE) ||
            files.digest(MigrationFileSlot.ACTIVE) != journal.activeDigest
        ) {
            return restoreRecovery(journal)
        }
        files.delete(MigrationFileSlot.ROLLBACK)
        files.delete(MigrationFileSlot.BACKUP)
        return persist(
            journal.copy(stage = MigrationJournalStage.CLEANUP_COMPLETE),
        )
    }

    @Synchronized
    fun finish(keyId: String) {
        val journal = requireKey(inspect(), keyId)
        requireStage(journal, MigrationJournalStage.CLEANUP_COMPLETE)
        journalStore.delete()
    }

    @Synchronized
    override fun isCleanupComplete(
        keyId: String,
        activeDigest: String,
    ): Boolean {
        return try {
            val journal = journalStore.read() ?: return false
            journal.stage == MigrationJournalStage.CLEANUP_COMPLETE &&
                journal.keyId == keyId &&
                journal.activeDigest == activeDigest &&
                files.digest(MigrationFileSlot.ACTIVE) == activeDigest
        } catch (_: Throwable) {
            false
        }
    }

    private fun resumeOldMoved(journal: MigrationJournal): MigrationJournal {
        if (
            files.exists(MigrationFileSlot.ROLLBACK) &&
            files.exists(MigrationFileSlot.PENDING) &&
            !files.exists(MigrationFileSlot.ACTIVE)
        ) {
            requireMainOnly(MigrationFileSlot.ROLLBACK)
            if (
                files.hasSidecars(MigrationFileSlot.PENDING) ||
                files.digest(MigrationFileSlot.PENDING) != journal.pendingDigest
            ) {
                return restoreRecovery(journal)
            }
            files.move(MigrationFileSlot.PENDING, MigrationFileSlot.ACTIVE)
            files.sync(MigrationFileSlot.ACTIVE)
            return persist(
                journal.copy(stage = MigrationJournalStage.NEW_ACTIVATED),
            )
        }
        return restoreRecovery(journal)
    }

    private fun resumeUnjournaledOldMove(
        journal: MigrationJournal,
    ): MigrationJournal {
        if (files.exists(MigrationFileSlot.ACTIVE)) {
            return journal
        }
        if (!files.exists(MigrationFileSlot.ROLLBACK)) {
            migrationFailure()
        }
        requireMainOnly(MigrationFileSlot.ROLLBACK)
        requireDigest(
            files.digest(MigrationFileSlot.ROLLBACK),
            journal.sourceDigest,
        )
        if (
            !files.exists(MigrationFileSlot.PENDING) ||
            files.hasSidecars(MigrationFileSlot.PENDING) ||
            files.digest(MigrationFileSlot.PENDING) != journal.pendingDigest
        ) {
            return restoreRecovery(journal)
        }
        return resumeOldMoved(
            persist(journal.copy(stage = MigrationJournalStage.OLD_MOVED)),
        )
    }

    private fun verifyActivatedOrRestore(
        journal: MigrationJournal,
    ): MigrationJournal {
        return if (
            files.digest(MigrationFileSlot.ACTIVE) == journal.pendingDigest
        ) {
            journal
        } else {
            restoreRecovery(journal)
        }
    }

    private fun restoreRecovery(journal: MigrationJournal): MigrationJournal {
        val source = listOf(
            MigrationFileSlot.ROLLBACK,
            MigrationFileSlot.BACKUP,
        ).firstOrNull { slot ->
            files.exists(slot) &&
                !files.hasSidecars(slot) &&
                files.digest(slot) == journal.sourceDigest
        } ?: migrationFailure()
        files.copy(source, MigrationFileSlot.ACTIVE)
        files.sync(MigrationFileSlot.ACTIVE)
        requireDigest(
            files.digest(MigrationFileSlot.ACTIVE),
            journal.sourceDigest,
        )
        files.delete(MigrationFileSlot.ROLLBACK)
        files.delete(MigrationFileSlot.PENDING)
        return persist(
            journal.copy(
                stage = MigrationJournalStage.BACKUP_READY,
                pendingDigest = null,
                activeDigest = null,
            ),
        )
    }

    private fun requireKey(
        journal: MigrationJournal,
        keyId: String,
    ): MigrationJournal {
        if (journal.keyId != keyId) {
            migrationFailure()
        }
        return journal
    }

    private fun requireStage(
        journal: MigrationJournal,
        expected: MigrationJournalStage,
    ) {
        if (journal.stage != expected) {
            migrationFailure()
        }
    }

    private fun requireDigest(actual: String?, expected: String?) {
        if (actual == null || actual != expected) {
            migrationFailure()
        }
    }

    private fun requireMainOnly(slot: MigrationFileSlot) {
        if (files.hasSidecars(slot)) {
            migrationFailure()
        }
    }

    private fun persist(value: MigrationJournal): MigrationJournal {
        journalStore.write(value)
        return value
    }

    private fun stateMap(value: MigrationJournal): Map<String, Any?> {
        return value.toChannelMap(files)
    }

    companion object {
        private const val MIGRATION_RESERVE_BYTES = 64L * 1024 * 1024
    }
}
