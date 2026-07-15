package com.example.note_secret_search.security

import android.content.Context
import android.content.ContextWrapper
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SecurityEnvelopeStoreInstrumentationTest {
    private lateinit var sandboxRoot: File
    private lateinit var keysetFile: File
    private lateinit var store: AtomicFileSecurityEnvelopeStore

    @Before
    fun setUp() {
        val targetContext = InstrumentationRegistry.getInstrumentation().targetContext
        sandboxRoot = File(
            targetContext.noBackupFilesDir,
            "instrumentation/security-envelope-store-${UUID.randomUUID()}",
        )
        val isolatedContext = object : ContextWrapper(targetContext) {
            override fun getNoBackupFilesDir(): File = sandboxRoot
        }
        keysetFile = File(sandboxRoot, "security/keyset-v2.json")
        store = AtomicFileSecurityEnvelopeStore(isolatedContext)
    }

    @After
    fun tearDown() {
        if (::sandboxRoot.isInitialized) {
            assertTrue(
                "Failed to delete instrumentation envelope files at $sandboxRoot",
                sandboxRoot.deleteRecursively(),
            )
        }
    }

    @Test
    fun readRecoversLastCommittedEnvelopeAfterInterruptedWrite() {
        val committedEnvelope = """{"version":2,"keyId":"committed"}"""
            .toByteArray(Charsets.UTF_8)
        val interruptedEnvelope = """{"version":2,"keyId":"""
            .toByteArray(Charsets.UTF_8)
        store.write(committedEnvelope)

        AtomicFile(keysetFile).startWrite().use { stream ->
            stream.write(interruptedEnvelope)
            stream.flush()
            stream.fd.sync()
        }

        val backupFile = File("${keysetFile.path}.bak")
        assertTrue("Expected AtomicFile to retain its backup.", backupFile.isFile)
        assertArrayEquals(interruptedEnvelope, keysetFile.readBytes())

        assertArrayEquals(committedEnvelope, store.read())
        assertArrayEquals(committedEnvelope, keysetFile.readBytes())
        assertFalse("Expected recovery to consume the backup.", backupFile.exists())
    }
}
