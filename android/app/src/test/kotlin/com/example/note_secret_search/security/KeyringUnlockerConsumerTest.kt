package com.example.note_secret_search.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal class KeyringUnlockerConsumerTest : SecurityKeyringTestFixture() {
    @Test
    fun `consumer failure is not reported as envelope corruption`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        val keyset = SecurityKeysetCodec.decode(store.bytes!!)
        val result = RecordingNativeResult<Unit>()
        var consumedMasterKey: ByteArray? = null

        KeyringUnlocker(keys, authenticator).withMasterKey(
            reason = "Consume master key",
            keyset = keyset,
            capabilities = capabilities,
            result = result,
        ) { masterKey ->
            consumedMasterKey = masterKey
            throw IllegalStateException("consumer failed")
        }

        assertEquals(
            NativeSecurityErrorCode.INTERNAL_ERROR,
            result.error?.code,
        )
        assertNull(result.value)
        assertTrue(consumedMasterKey!!.all { it == 0.toByte() })
    }

    @Test
    fun `consumer security error keeps its stable error code`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 30).provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        val keyset = SecurityKeysetCodec.decode(store.bytes!!)
        val result = RecordingNativeResult<Unit>()

        KeyringUnlocker(keys, authenticator).withMasterKey(
            reason = "Consume master key",
            keyset = keyset,
            capabilities = capabilities,
            result = result,
        ) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            )
        }

        assertEquals(
            NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            result.error?.code,
        )
        assertNull(result.value)
    }
}
