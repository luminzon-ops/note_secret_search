package com.example.note_secret_search

import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class EmbeddingCancellationBoundaryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `checksum cancellation during a chunk remains CANCELLED`() {
        val cancellation = CancellationHandle()
        val verifier = Sha256EmbeddingModelChecksumVerifier(
            inputStreamFactory = {
                object : FilterInputStream(ByteArrayInputStream(byteArrayOf(1, 2, 3))) {
                    private var firstRead = true

                    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                        val count = super.read(buffer, offset, length)
                        if (count > 0 && firstRead) {
                            firstRead = false
                            cancellation.cancel(cancelledError())
                        }
                        return count
                    }
                }
            },
        )

        val error = try {
            verifier.verify(
                file = temporaryFolder.newFile("model.onnx"),
                expectedChecksum = null,
                modelId = "embedding-model",
                cancellation = cancellation,
            )
            null
        } catch (caught: EmbeddingRuntimeException) {
            caught
        }

        assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, error?.code)
    }

    @Test
    fun `tokenizer checks cancellation before processing text`() {
        val cancellation = CancellationHandle()
        cancellation.cancel(cancelledError())
        val tokenizer = WordpieceEmbeddingTokenizer(
            vocab = mapOf(
                "[PAD]" to 0,
                "[UNK]" to 100,
                "[CLS]" to 101,
                "[SEP]" to 102,
            ),
            lowercase = false,
            maxSequenceLength = 8,
        )

        val error = try {
            tokenizer.encode("TEXT_SENTINEL", cancellation = cancellation)
            null
        } catch (caught: EmbeddingRuntimeException) {
            caught
        }

        assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, error?.code)
    }

    private fun cancelledError(): EmbeddingRuntimeException {
        return EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.CANCELLED,
            stage = EmbeddingRuntimeStage.CHECKSUM,
            modelId = "embedding-model",
        )
    }
}
