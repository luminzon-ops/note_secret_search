package com.example.note_secret_search

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

class CancellationHandle {
    private val cancellation = AtomicReference<EmbeddingRuntimeException?>()
    private val listeners = CopyOnWriteArrayList<CancellationListener>()
    private val cancelledLatch = CountDownLatch(1)

    val isCancelled: Boolean
        get() = cancellation.get() != null

    fun cancel(error: EmbeddingRuntimeException): Boolean {
        if (!cancellation.compareAndSet(null, error)) {
            return false
        }
        cancelledLatch.countDown()
        listeners.forEach { listener ->
            listeners.remove(listener)
            listener.invoke()
        }
        return true
    }

    fun throwIfCancelled(modelId: String? = null) {
        cancellation.get()?.let { error ->
            throw error.withModelId(modelId)
        }
    }

    fun errorOrNull(modelId: String? = null): EmbeddingRuntimeException? {
        return cancellation.get()?.withModelId(modelId)
    }

    fun registerTerminator(terminate: () -> Unit): AutoCloseable {
        val listener = CancellationListener(terminate)
        if (isCancelled) {
            listener.invoke()
            return listener
        }
        listeners.add(listener)
        if (isCancelled && listeners.remove(listener)) {
            listener.invoke()
        }
        return AutoCloseable {
            listeners.remove(listener)
            listener.close()
        }
    }

    fun awaitCancellation() {
        cancelledLatch.await()
    }
}

private class CancellationListener(
    private val terminate: () -> Unit,
) : AutoCloseable {
    private val lock = Any()
    private var active = true

    fun invoke() {
        synchronized(lock) {
            if (!active) {
                return
            }
            active = false
            try {
                terminate()
            } catch (_: Throwable) {
                // Cancellation must remain best-effort and never expose native details.
            }
        }
    }

    override fun close() {
        synchronized(lock) {
            active = false
        }
    }
}
