package com.example.note_secret_search

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddingRuntimeWorkerCancellationTest {
    @Test
    fun `queued cancellation removes work and restores bounded capacity`() {
        val runningStarted = CountDownLatch(1)
        val allowRunning = CountDownLatch(1)
        val queuedDropped = CountDownLatch(1)
        val queuedExecuted = AtomicBoolean(false)
        val worker = testWorker(capacity = 2)

        try {
            assertEquals(
                EmbeddingWorkSubmission.ACCEPTED,
                worker.submit(
                    workItem(
                        requestId = "running",
                        execute = {
                            runningStarted.countDown()
                            allowRunning.await(2, TimeUnit.SECONDS)
                        },
                    ),
                ),
            )
            assertTrue(runningStarted.await(1, TimeUnit.SECONDS))
            assertEquals(
                EmbeddingWorkSubmission.ACCEPTED,
                worker.submit(
                    workItem(
                        requestId = "queued",
                        execute = { queuedExecuted.set(true) },
                        onDropped = { error ->
                            assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, error.code)
                            queuedDropped.countDown()
                        },
                    ),
                ),
            )

            assertTrue(worker.cancelRequest("queued"))
            assertTrue(queuedDropped.await(1, TimeUnit.SECONDS))
            assertFalse(queuedExecuted.get())
            assertEquals(
                EmbeddingWorkSubmission.ACCEPTED,
                worker.submit(workItem(requestId = "replacement")),
            )
        } finally {
            allowRunning.countDown()
            worker.close()
        }
    }

    @Test
    fun `running cancellation signals the active cancellation handle`() {
        val started = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val observedCode = arrayOfNulls<EmbeddingRuntimeErrorCode>(1)
        val cancellation = CancellationHandle()
        val worker = testWorker()

        try {
            worker.submit(
                workItem(
                    requestId = "running",
                    cancellation = cancellation,
                    execute = {
                        started.countDown()
                        cancellation.awaitCancellation()
                        try {
                            cancellation.throwIfCancelled("embedding-model")
                        } catch (error: EmbeddingRuntimeException) {
                            observedCode[0] = error.code
                        } finally {
                            finished.countDown()
                        }
                    },
                ),
            )

            assertTrue(started.await(1, TimeUnit.SECONDS))
            assertTrue(worker.cancelRequest("running"))
            assertTrue(finished.await(1, TimeUnit.SECONDS))
            assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, observedCode[0])
        } finally {
            worker.close()
        }
    }

    @Test
    fun `release cancels matching work and runs before unrelated queued work`() {
        val events = Collections.synchronizedList(mutableListOf<String>())
        val runningStarted = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val runningCancellation = CancellationHandle()
        val worker = testWorker(capacity = 4)

        try {
            worker.submit(
                workItem(
                    modelId = "model-a",
                    requestId = "running-a",
                    cancellation = runningCancellation,
                    execute = {
                        events += "start-a"
                        runningStarted.countDown()
                        runningCancellation.awaitCancellation()
                        events += "cancel-running-a"
                    },
                ),
            )
            assertTrue(runningStarted.await(1, TimeUnit.SECONDS))
            worker.submit(
                workItem(
                    modelId = "model-a",
                    requestId = "queued-a",
                    execute = { events += "run-queued-a" },
                    onDropped = { error ->
                        assertEquals(EmbeddingRuntimeErrorCode.CANCELLED, error.code)
                        events += "drop-queued-a"
                    },
                ),
            )
            worker.submit(
                workItem(
                    modelId = "model-b",
                    requestId = "queued-b",
                    execute = {
                        events += "run-b"
                        finished.countDown()
                    },
                ),
            )

            assertEquals(
                EmbeddingWorkSubmission.ACCEPTED,
                worker.submitRelease(
                    workItem(
                        modelId = "model-a",
                        execute = { events += "release-a" },
                    ),
                ),
            )

            assertTrue(finished.await(1, TimeUnit.SECONDS))
            assertEquals(
                listOf(
                    "start-a",
                    "drop-queued-a",
                    "cancel-running-a",
                    "release-a",
                    "run-b",
                ),
                events,
            )
        } finally {
            worker.close()
        }
    }

    @Test
    fun `shutdown cancels all work and runs terminal cleanup on worker`() {
        val runningStarted = CountDownLatch(1)
        val cleanupFinished = CountDownLatch(1)
        val runningCancellation = CancellationHandle()
        val queuedError = arrayOfNulls<EmbeddingRuntimeErrorCode>(1)
        var cleanupThreadName: String? = null
        val worker = testWorker(capacity = 2)

        worker.submit(
            workItem(
                requestId = "running",
                cancellation = runningCancellation,
                execute = {
                    runningStarted.countDown()
                    runningCancellation.awaitCancellation()
                    runningCancellation.throwIfCancelled()
                },
            ),
        )
        assertTrue(runningStarted.await(1, TimeUnit.SECONDS))
        worker.submit(
            workItem(
                requestId = "queued",
                onDropped = { error -> queuedError[0] = error.code },
            ),
        )

        val startedAt = System.nanoTime()
        worker.shutdown {
            cleanupThreadName = Thread.currentThread().name
            cleanupFinished.countDown()
        }
        val elapsedMillis =
            TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

        assertTrue(elapsedMillis < 100)
        assertTrue(cleanupFinished.await(1, TimeUnit.SECONDS))
        assertEquals(EmbeddingRuntimeErrorCode.RUNTIME_CLOSED, queuedError[0])
        assertEquals("embedding-runtime-worker", cleanupThreadName)
        assertEquals(
            EmbeddingWorkSubmission.CLOSED,
            worker.submit(workItem(requestId = "late")),
        )
    }

    private fun testWorker(capacity: Int = 8): EmbeddingRuntimeWorker {
        return EmbeddingRuntimeWorker(
            capacity = capacity,
            threadPrioritySetter = {},
        )
    }

    private fun workItem(
        modelId: String = "embedding-model",
        requestId: String? = null,
        cancellation: CancellationHandle = CancellationHandle(),
        execute: () -> Unit = {},
        onDropped: (EmbeddingRuntimeException) -> Unit = {},
    ): EmbeddingWorkItem {
        return EmbeddingWorkItem(
            modelId = modelId,
            requestId = requestId,
            cancellation = cancellation,
            execute = execute,
            onDropped = onDropped,
        )
    }
}
