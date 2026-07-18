package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Test

internal class MigrationJournalCodecTest {
    @Test
    fun `every durable stage round trips with its required metadata`() {
        MigrationJournalStage.entries.forEach { stage ->
            val expected = journal(stage)

            val decoded = MigrationJournalCodec.decode(
                MigrationJournalCodec.encode(expected),
            )

            assertEquals(expected, decoded)
        }
    }

    @Test
    fun `unknown stage is rejected`() {
        expectMigrationFailure(
            validJson().replace("\"detected\"", "\"invented\""),
        )
    }

    @Test
    fun `extra journal properties are rejected`() {
        expectMigrationFailure(
            validJson().replace(
                "\"activeDigest\":null",
                "\"activeDigest\":null,\"unexpected\":true",
            ),
        )
    }

    @Test
    fun `non canonical key identifiers are rejected`() {
        expectMigrationFailure(
            encoded(journal(MigrationJournalStage.KEYRING_READY)).replace(
                KEY_ID,
                KEY_ID.uppercase(),
            ),
        )
    }

    @Test
    fun `metadata from a future stage is rejected`() {
        expectMigrationFailure(
            validJson().replace(
                "\"sourceDigest\":null",
                "\"sourceDigest\":\"${"a".repeat(64)}\"",
            ),
        )
    }

    @Test
    fun `missing required digest is rejected`() {
        expectMigrationFailure(
            encoded(journal(MigrationJournalStage.VALIDATED)).replace(
                "\"pendingDigest\":\"${"b".repeat(64)}\"",
                "\"pendingDigest\":null",
            ),
        )
    }

    @Test
    fun `malformed digest is rejected`() {
        expectMigrationFailure(
            encoded(journal(MigrationJournalStage.BACKUP_READY)).replace(
                "a".repeat(64),
                "A".repeat(64),
            ),
        )
    }

    private fun expectMigrationFailure(json: String) {
        val error = try {
            MigrationJournalCodec.decode(json.toByteArray())
            throw AssertionError("Expected migration journal rejection")
        } catch (error: NativeSecurityException) {
            error
        }
        assertEquals(NativeSecurityErrorCode.MIGRATION_FAILED, error.code)
    }

    private fun validJson(): String {
        return encoded(journal(MigrationJournalStage.DETECTED))
    }

    private fun encoded(journal: MigrationJournal): String {
        return MigrationJournalCodec.encode(journal).toString(Charsets.UTF_8)
    }

    private fun journal(stage: MigrationJournalStage): MigrationJournal {
        return MigrationJournal(
            stage = stage,
            keyId = if (stage >= MigrationJournalStage.KEYRING_READY) {
                KEY_ID
            } else {
                null
            },
            sourceDigest = if (stage >= MigrationJournalStage.BACKUP_READY) {
                "a".repeat(64)
            } else {
                null
            },
            pendingDigest = if (stage >= MigrationJournalStage.VALIDATED) {
                "b".repeat(64)
            } else {
                null
            },
            activeDigest = if (
                stage >= MigrationJournalStage.POST_SWAP_VALIDATED
            ) {
                "b".repeat(64)
            } else {
                null
            },
        )
    }

    companion object {
        private const val KEY_ID =
            "123e4567-e89b-42d3-a456-426614174000"
    }
}
