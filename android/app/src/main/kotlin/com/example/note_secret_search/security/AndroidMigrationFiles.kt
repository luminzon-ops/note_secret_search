package com.example.note_secret_search.security

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.security.MessageDigest

class AtomicFileMigrationJournalStore(
    context: Context,
) : MigrationJournalStore {
    private val file = File(
        context.noBackupFilesDir,
        "security/migration-v2/journal.json",
    )
    private val atomicFile = AtomicFile(file)

    override fun read(): MigrationJournal? {
        return try {
            readRecoverableAtomicFile(
                stateFilesExist = {
                    file.exists() ||
                        File("${file.path}.bak").exists() ||
                        File("${file.path}.new").exists()
                },
                readFully = atomicFile::readFully,
            )?.let(MigrationJournalCodec::decode)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_FAILED,
                error,
            )
        }
    }

    override fun write(value: MigrationJournal) {
        val parent = atomicFile.baseFile.parentFile ?: migrationFailure()
        if (!parent.exists() && !parent.mkdirs()) {
            migrationFailure()
        }
        var output: FileOutputStream? = null
        try {
            output = atomicFile.startWrite()
            output.write(MigrationJournalCodec.encode(value))
            output.flush()
            atomicFile.finishWrite(output)
            output = null
            syncDirectory(parent)
        } catch (error: NativeSecurityException) {
            throw error
        } catch (error: Exception) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.MIGRATION_FAILED,
                error,
            )
        } finally {
            output?.let(atomicFile::failWrite)
        }
    }

    override fun delete() {
        atomicFile.delete()
        file.parentFile?.let(::syncDirectory)
    }
}

private data class AndroidMigrationPaths(
    val bases: Map<MigrationFileSlot, File>,
    val workspace: File,
)

class AndroidMigrationFileSetAccess private constructor(
    paths: AndroidMigrationPaths,
) : MigrationFileSetAccess {
    private val bases = paths.bases
    private val workspace = paths.workspace

    constructor(context: Context) : this(
        activeDatabase = context.getDatabasePath(DATABASE_NAME),
        workspace = File(
            context.noBackupFilesDir,
            "security/migration-v2",
        ),
    )

    internal constructor(
        activeDatabase: File,
        workspace: File,
    ) : this(validatePaths(activeDatabase, workspace))

    override fun path(slot: MigrationFileSlot): String {
        return base(slot).absolutePath
    }

    override fun exists(slot: MigrationFileSlot): Boolean = base(slot).isFile

    override fun hasSidecars(slot: MigrationFileSlot): Boolean {
        val base = base(slot)
        return File("${base.path}-wal").exists() ||
            File("${base.path}-shm").exists()
    }

    override fun sizeBytes(slot: MigrationFileSlot): Long {
        return members(slot).filter(File::isFile).sumOf(File::length)
    }

    override fun availableBytes(): Long {
        ensureDirectory(workspace)
        return workspace.usableSpace
    }

    override fun digest(slot: MigrationFileSlot): String? {
        if (!exists(slot)) {
            return null
        }
        val digest = MessageDigest.getInstance("SHA-256")
        members(slot).forEachIndexed { index, file ->
            if (!file.isFile) {
                return@forEachIndexed
            }
            val role = SUFFIXES[index].ifEmpty { "main" }
            digest.update(role.toByteArray(Charsets.US_ASCII))
            digest.update(0)
            digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(file.length()).array())
            FileInputStream(file).use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) {
                        break
                    }
                    digest.update(buffer, 0, count)
                }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    override fun copy(from: MigrationFileSlot, to: MigrationFileSlot) {
        if (!exists(from) || hasSidecars(from)) {
            migrationFailure()
        }
        delete(to)
        val source = base(from)
        val target = base(to)
        ensureDirectory(checkNotNull(target.parentFile))
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
                output.flush()
                output.fd.sync()
            }
        }
        syncDirectory(checkNotNull(base(to).parentFile))
    }

    override fun move(from: MigrationFileSlot, to: MigrationFileSlot) {
        if (!exists(from) || hasSidecars(from)) {
            migrationFailure()
        }
        delete(to)
        val source = base(from)
        val target = base(to)
        ensureDirectory(checkNotNull(target.parentFile))
        if (!source.renameTo(target)) {
            migrationFailure()
        }
        base(from).parentFile?.let(::syncDirectory)
        base(to).parentFile?.let(::syncDirectory)
    }

    override fun delete(slot: MigrationFileSlot) {
        members(slot).forEach { file ->
            if (file.exists() && !file.delete()) {
                migrationFailure()
            }
        }
        base(slot).parentFile?.let { parent ->
            if (parent.exists()) {
                syncDirectory(parent)
            }
        }
    }

    override fun sync(slot: MigrationFileSlot) {
        members(slot).filter(File::isFile).forEach { file ->
            RandomAccessFile(file, "rw").use { it.fd.sync() }
        }
        base(slot).parentFile?.let(::syncDirectory)
    }

    private fun members(slot: MigrationFileSlot): List<File> {
        val base = base(slot)
        return SUFFIXES.map { suffix -> File("${base.path}$suffix") }
    }

    private fun base(slot: MigrationFileSlot): File {
        return checkNotNull(bases[slot])
    }

    companion object {
        private const val DATABASE_NAME = "note_secret_search.db"
        private val SUFFIXES = listOf("", "-wal", "-shm")

        private fun validatePaths(
            activeDatabase: File,
            workspace: File,
        ): AndroidMigrationPaths {
            try {
                val canonicalWorkspace = workspace.canonicalFile
                if (
                    canonicalWorkspace.exists() &&
                    !canonicalWorkspace.isDirectory
                ) {
                    migrationFailure()
                }
                val canonicalBases = mapOf(
                    MigrationFileSlot.ACTIVE to activeDatabase.canonicalFile,
                    MigrationFileSlot.BACKUP to
                        File(canonicalWorkspace, "backup/$DATABASE_NAME").canonicalFile,
                    MigrationFileSlot.PENDING to
                        File(canonicalWorkspace, "pending/$DATABASE_NAME").canonicalFile,
                    MigrationFileSlot.ROLLBACK to
                        File(canonicalWorkspace, "rollback/$DATABASE_NAME").canonicalFile,
                )
                val workspacePath = canonicalWorkspace.toPath()
                val activePath = checkNotNull(
                    canonicalBases[MigrationFileSlot.ACTIVE],
                ).toPath()
                if (
                    activePath == workspacePath ||
                    activePath.startsWith(workspacePath)
                ) {
                    migrationFailure()
                }
                canonicalBases
                    .filterKeys { it != MigrationFileSlot.ACTIVE }
                    .values
                    .forEach { file ->
                        val path = file.toPath()
                        if (
                            path == workspacePath ||
                            !path.startsWith(workspacePath)
                        ) {
                            migrationFailure()
                        }
                    }

                val memberPaths = mutableSetOf<java.nio.file.Path>()
                canonicalBases.values.forEach { base ->
                    SUFFIXES.forEach { suffix ->
                        val member = File("${base.path}$suffix")
                            .canonicalFile
                            .toPath()
                        if (!memberPaths.add(member)) {
                            migrationFailure()
                        }
                    }
                }
                return AndroidMigrationPaths(
                    bases = canonicalBases,
                    workspace = canonicalWorkspace,
                )
            } catch (error: NativeSecurityException) {
                throw error
            } catch (error: Exception) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.MIGRATION_FAILED,
                    error,
                )
            }
        }
    }
}

private fun ensureDirectory(directory: File) {
    if (!directory.exists() && !directory.mkdirs()) {
        migrationFailure()
    }
}

private fun syncDirectory(directory: File) {
    val descriptor = Os.open(
        directory.absolutePath,
        OsConstants.O_RDONLY,
        0,
    )
    try {
        Os.fsync(descriptor)
    } finally {
        Os.close(descriptor)
    }
}
