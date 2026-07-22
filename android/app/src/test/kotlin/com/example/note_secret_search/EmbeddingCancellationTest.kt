package com.example.note_secret_search

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddingCancellationTest {
    @Test
    fun `cancel invokes each registered terminator exactly once`() {
        val calls = AtomicInteger()
        val cancellation = CancellationHandle()
        cancellation.registerTerminator { calls.incrementAndGet() }

        assertTrue(cancellation.cancel(cancelledError()))
        assertFalse(cancellation.cancel(cancelledError()))
        assertEquals(1, calls.get())
    }

    @Test
    fun `closing a terminator unregisters it before cancellation`() {
        val calls = AtomicInteger()
        val cancellation = CancellationHandle()
        val registration = cancellation.registerTerminator { calls.incrementAndGet() }

        registration.close()
        assertTrue(cancellation.cancel(cancelledError()))
        assertEquals(0, calls.get())
    }

    @Test
    fun `registering after cancellation invokes immediately once`() {
        val calls = AtomicInteger()
        val cancellation = CancellationHandle()
        assertTrue(cancellation.cancel(cancelledError()))

        val registration = cancellation.registerTerminator { calls.incrementAndGet() }
        registration.close()

        assertEquals(1, calls.get())
    }

    private fun cancelledError(): EmbeddingRuntimeException {
        return EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.CANCELLED,
            stage = EmbeddingRuntimeStage.LIFECYCLE,
            modelId = "embedding-model",
        )
    }
}
