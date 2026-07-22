package com.example.note_secret_search

import android.os.Process
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

interface EmbeddingRuntimeContract {
    fun inspectModel(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?>

    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?>

    fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
    ): Map<String, Any?>

    fun releaseModel(modelId: String)

    fun releaseAll()
}

data class EmbeddingWorkItem(
    val modelId: String?,
    val requestId: String? = null,
    val execute: () -> Unit,
    val onDropped: (EmbeddingRuntimeException) -> Unit,
)

enum class EmbeddingWorkSubmission {
    ACCEPTED,
    BUSY,
    CLOSED,
}

class EmbeddingRuntimeWorker(
    private val capacity: Int = DEFAULT_CAPACITY,
    private val threadPrioritySetter: () -> Unit = {
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
    },
) : AutoCloseable {
    private val queue = LinkedBlockingDeque<EmbeddingWorkItem>(capacity)
    private val outstanding = AtomicInteger(0)
    private val closed = AtomicBoolean(false)
    private val lock = Any()
    private val workerThread = Thread(::runLoop, THREAD_NAME).apply {
        isDaemon = true
        start()
    }

    init {
        require(capacity > 0)
    }

    fun submit(item: EmbeddingWorkItem): EmbeddingWorkSubmission {
        synchronized(lock) {
            if (closed.get()) {
                return EmbeddingWorkSubmission.CLOSED
            }
            if (outstanding.get() >= capacity) {
                return EmbeddingWorkSubmission.BUSY
            }
            outstanding.incrementAndGet()
            if (!queue.offerLast(item)) {
                outstanding.decrementAndGet()
                return EmbeddingWorkSubmission.BUSY
            }
            return EmbeddingWorkSubmission.ACCEPTED
        }
    }

    override fun close() {
        val dropped = mutableListOf<EmbeddingWorkItem>()
        synchronized(lock) {
            if (!closed.compareAndSet(false, true)) {
                return
            }
            queue.drainTo(dropped)
            outstanding.addAndGet(-dropped.size)
        }
        val error = EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.RUNTIME_CLOSED,
            stage = EmbeddingRuntimeStage.LIFECYCLE,
        )
        dropped.forEach { item -> item.onDropped(error.withModelId(item.modelId)) }
        workerThread.interrupt()
        if (Thread.currentThread() !== workerThread) {
            workerThread.join(CLOSE_JOIN_MILLIS)
        }
    }

    private fun runLoop() {
        threadPrioritySetter()
        while (!closed.get()) {
            val item = try {
                queue.takeFirst()
            } catch (_: InterruptedException) {
                if (closed.get()) {
                    break
                }
                continue
            }
            try {
                item.execute()
            } finally {
                outstanding.decrementAndGet()
            }
        }
    }

    companion object {
        const val DEFAULT_CAPACITY = 8
        private const val THREAD_NAME = "embedding-runtime-worker"
        private const val CLOSE_JOIN_MILLIS = 2_000L
    }
}
