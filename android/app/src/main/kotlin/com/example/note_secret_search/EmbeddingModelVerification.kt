package com.example.note_secret_search

import java.io.File
import java.security.MessageDigest

data class LoadedEmbeddingTokenizer(
    val tokenizer: WordpieceEmbeddingTokenizer,
    val contentSha256: String,
) {
    init {
        require(SHA256_PATTERN.matches(contentSha256))
    }

    companion object {
        private val SHA256_PATTERN = Regex("^sha256:[0-9a-f]{64}$")
    }
}

fun interface EmbeddingModelChecksumVerifier {
    fun verify(
        file: File,
        expectedChecksum: String?,
        modelId: String,
        cancellation: CancellationHandle,
    ): String
}

class Sha256EmbeddingModelChecksumVerifier(
    private val inputStreamFactory: (File) -> java.io.InputStream = File::inputStream,
) : EmbeddingModelChecksumVerifier {
    override fun verify(
        file: File,
        expectedChecksum: String?,
        modelId: String,
        cancellation: CancellationHandle,
    ): String {
        cancellation.throwIfCancelled(modelId)
        if (!file.isFile || !file.canRead()) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.MODEL_MISSING,
                stage = EmbeddingRuntimeStage.MODEL_LOOKUP,
                modelId = modelId,
            )
        }
        val expected = expectedChecksum?.let {
            normalizeSha256(it, modelId)
        }
        val actual = try {
            inputStreamFactory(file).buffered(HASH_BUFFER_BYTES).use { input ->
                val digest = MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(HASH_BUFFER_BYTES)
                while (true) {
                    cancellation.throwIfCancelled(modelId)
                    val read = input.read(buffer)
                    if (read < 0) {
                        break
                    }
                    if (read > 0) {
                        digest.update(buffer, 0, read)
                    }
                }
                cancellation.throwIfCancelled(modelId)
                digest.digest().toSha256String()
            }
        } catch (error: Throwable) {
            cancellation.errorOrNull(modelId)?.let { throw it }
            throw EmbeddingRuntimeException.wrap(
                error = error,
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.CHECKSUM,
                modelId = modelId,
            )
        }
        if (expected != null && actual != expected) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.CHECKSUM_MISMATCH,
                stage = EmbeddingRuntimeStage.CHECKSUM,
                modelId = modelId,
            )
        }
        return actual
    }

    private fun normalizeSha256(
        checksum: String,
        modelId: String,
    ): String {
        val normalized = checksum.lowercase()
        if (!SHA256_PATTERN.matches(normalized)) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.INVALID_ARGUMENT,
                stage = EmbeddingRuntimeStage.CHECKSUM,
                modelId = modelId,
            )
        }
        return normalized
    }

    companion object {
        private const val HASH_BUFFER_BYTES = 1024 * 1024
        private val SHA256_PATTERN = Regex("^sha256:[0-9a-f]{64}$")
    }
}

fun sha256String(bytes: ByteArray): String {
    return MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .toSha256String()
}

private fun ByteArray.toSha256String(): String {
    return buildString(7 + size * 2) {
        append("sha256:")
        this@toSha256String.forEach { byte ->
            append(((byte.toInt() ushr 4) and 0x0f).toString(16))
            append((byte.toInt() and 0x0f).toString(16))
        }
    }
}
