package com.example.note_secret_search

import android.os.Process
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.atomic.AtomicBoolean

interface EmbeddingRuntimeContract : AutoCloseable {
    fun inspectModel(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String? = null,
        cancellation: CancellationHandle = CancellationHandle(),
    ): Map<String, Any?>

    fun ensureModelReady(
        modelId: String,
        modelPath: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String? = null,
        cancellation: CancellationHandle = CancellationHandle(),
    ): Map<String, Any?>

    fun embedText(
        modelId: String,
        modelPath: String,
        text: String,
        spec: OnnxEmbeddingModelSpec,
        verifiedChecksum: String? = null,
        requestId: String? = null,
        cancellation: CancellationHandle = CancellationHandle(),
    ): Map<String, Any?>

    fun releaseModel(modelId: String)

    fun releaseAll()

    override fun close() {
        releaseAll()
    }
}

class EmbeddingWorkItem(
    val modelId: String?,
    val requestId: String? = null,
    val cancellation: CancellationHandle = CancellationHandle(),
    val execute: () -> Unit,
    val onDropped: (EmbeddingRuntimeException) -> Unit,
) {
    internal var countsAgainstCapacity: Boolean = true
}

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
    private val queue = LinkedBlockingDeque<EmbeddingWorkItem>(capacity + CONTROL_QUEUE_SLOTS)
    private val closed = AtomicBoolean(false)
    private val lock = Any()
    private val outstandingItems = linkedSetOf<EmbeddingWorkItem>()
    private var ordinaryOutstanding = 0
    private var terminalCleanup: (() -> Unit)? = null
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
            if (ordinaryOutstanding >= capacity) {
                return EmbeddingWorkSubmission.BUSY
            }
            if (item.requestId != null && outstandingItems.any {
                    it.requestId == item.requestId
                }
            ) {
                return EmbeddingWorkSubmission.BUSY
            }
            ordinaryOutstanding += 1
            item.countsAgainstCapacity = true
            outstandingItems.add(item)
            if (!queue.offerLast(item)) {
                outstandingItems.remove(item)
                ordinaryOutstanding -= 1
                return EmbeddingWorkSubmission.BUSY
            }
            return EmbeddingWorkSubmission.ACCEPTED
        }
    }

    fun cancelRequest(requestId: String): Boolean {
        if (requestId.isBlank()) {
            return false
        }
        val error = cancellationError()
        var queued: EmbeddingWorkItem? = null
        var active: EmbeddingWorkItem? = null
        synchronized(lock) {
            val item = outstandingItems.firstOrNull { it.requestId == requestId }
                ?: return false
            if (queue.remove(item)) {
                removeOutstanding(item)
                queued = item
            } else {
                active = item
            }
        }
        queued?.let { item ->
            item.cancellation.cancel(error.withModelId(item.modelId))
            item.onDropped(error.withModelId(item.modelId))
        }
        active?.cancellation?.cancel(error.withModelId(active?.modelId))
        return true
    }

    fun submitRelease(item: EmbeddingWorkItem): EmbeddingWorkSubmission {
        val modelId = item.modelId ?: return EmbeddingWorkSubmission.BUSY
        val dropped = mutableListOf<EmbeddingWorkItem>()
        val active = mutableListOf<EmbeddingWorkItem>()
        val error = cancellationError(modelId)
        synchronized(lock) {
            if (closed.get()) {
                return EmbeddingWorkSubmission.CLOSED
            }
            outstandingItems
                .filter { existing -> existing.modelId == modelId }
                .forEach { existing ->
                    if (queue.remove(existing)) {
                        removeOutstanding(existing)
                        dropped.add(existing)
                    } else {
                        active.add(existing)
                    }
                }
            item.countsAgainstCapacity = false
            outstandingItems.add(item)
            if (!queue.offerFirst(item)) {
                outstandingItems.remove(item)
                return EmbeddingWorkSubmission.BUSY
            }
        }
        dropped.forEach { existing ->
            existing.cancellation.cancel(error)
            existing.onDropped(error)
        }
        active.forEach { existing ->
            existing.cancellation.cancel(error)
        }
        return EmbeddingWorkSubmission.ACCEPTED
    }

    fun shutdown(cleanup: () -> Unit = {}) {
        val dropped = mutableListOf<EmbeddingWorkItem>()
        val active = mutableListOf<EmbeddingWorkItem>()
        val error = EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.RUNTIME_CLOSED,
            stage = EmbeddingRuntimeStage.LIFECYCLE,
        )
        synchronized(lock) {
            if (!closed.compareAndSet(false, true)) {
                return
            }
            terminalCleanup = cleanup
            outstandingItems.toList().forEach { item ->
                if (queue.remove(item)) {
                    removeOutstanding(item)
                    dropped.add(item)
                } else {
                    active.add(item)
                }
            }
        }
        dropped.forEach { item ->
            val typed = error.withModelId(item.modelId)
            item.cancellation.cancel(typed)
            item.onDropped(typed)
        }
        active.forEach { item ->
            item.cancellation.cancel(error.withModelId(item.modelId))
        }
        workerThread.interrupt()
    }

    override fun close() {
        shutdown()
    }

    private fun runLoop() {
        threadPrioritySetter()
        try {
            while (true) {
                val item = try {
                    queue.takeFirst()
                } catch (_: InterruptedException) {
                    if (closed.get()) {
                        break
                    }
                    continue
                }
                try {
                    if (closed.get() && !item.cancellation.isCancelled) {
                        item.cancellation.cancel(
                            EmbeddingRuntimeException(
                                code = EmbeddingRuntimeErrorCode.RUNTIME_CLOSED,
                                stage = EmbeddingRuntimeStage.LIFECYCLE,
                                modelId = item.modelId,
                            ),
                        )
                    }
                    val cancellation = item.cancellation.errorOrNull(item.modelId)
                    if (cancellation != null) {
                        item.onDropped(cancellation)
                    } else {
                        try {
                            item.execute()
                        } catch (_: Throwable) {
                            // Plugin work items translate their own failures.
                        }
                    }
                } finally {
                    synchronized(lock) {
                        removeOutstanding(item)
                    }
                }
                if (closed.get()) {
                    break
                }
            }
        } finally {
            val cleanup = synchronized(lock) {
                terminalCleanup.also { terminalCleanup = null }
            }
            try {
                cleanup?.invoke()
            } catch (_: Throwable) {
                // Teardown is terminal and must not revive the worker.
            }
        }
    }

    private fun removeOutstanding(item: EmbeddingWorkItem) {
        if (outstandingItems.remove(item) && item.countsAgainstCapacity) {
            ordinaryOutstanding -= 1
        }
    }

    private fun cancellationError(
        modelId: String? = null,
    ): EmbeddingRuntimeException {
        return EmbeddingRuntimeException(
            code = EmbeddingRuntimeErrorCode.CANCELLED,
            stage = EmbeddingRuntimeStage.LIFECYCLE,
            modelId = modelId,
        )
    }

    companion object {
        const val DEFAULT_CAPACITY = 8
        private const val THREAD_NAME = "embedding-runtime-worker"
        private const val CONTROL_QUEUE_SLOTS = 1
    }
}
