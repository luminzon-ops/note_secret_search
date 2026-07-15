package com.example.note_secret_search.security

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream

interface SecurityEnvelopeStore {
    fun read(): ByteArray?

    fun write(value: ByteArray)
}

class AtomicFileSecurityEnvelopeStore private constructor(
    private val access: AtomicFileAccess,
) : SecurityEnvelopeStore {
    constructor(context: Context) : this(
        AndroidAtomicFileAccess(
            File(context.noBackupFilesDir, "security/keyset-v2.json"),
        ),
    )

    override fun read(): ByteArray? {
        return try {
            access.read()
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                error,
            )
        }
    }

    override fun write(value: ByteArray) {
        try {
            access.write(value)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
                error,
            )
        }
    }
}

private interface AtomicFileAccess {
    fun read(): ByteArray?

    fun write(value: ByteArray)
}

private class AndroidAtomicFileAccess(
    file: File,
) : AtomicFileAccess {
    private val atomicFile = AtomicFile(file)

    override fun read(): ByteArray? {
        if (!atomicFile.baseFile.exists()) {
            return null
        }
        return atomicFile.readFully()
    }

    override fun write(value: ByteArray) {
        val parent = atomicFile.baseFile.parentFile
        if (parent == null || (!parent.exists() && !parent.mkdirs())) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            )
        }
        var stream: FileOutputStream? = null
        try {
            stream = atomicFile.startWrite()
            stream.write(value)
            stream.flush()
            atomicFile.finishWrite(stream)
            stream = null
        } finally {
            stream?.let(atomicFile::failWrite)
        }
    }
}
