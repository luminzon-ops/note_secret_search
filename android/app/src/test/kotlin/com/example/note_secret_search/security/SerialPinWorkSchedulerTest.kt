package com.example.note_secret_search.security

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SerialPinWorkSchedulerTest {
    @Test
    fun `cancelling active pin work waits for task cleanup`() {
        val scheduler = SerialPinWorkScheduler()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cleaned = CountDownLatch(1)
        val cancelReturned = CountDownLatch(1)
        val handle = scheduler.execute {
            started.countDown()
            try {
                while (true) {
                    try {
                        release.await()
                        break
                    } catch (_: InterruptedException) {
                        // Model native Argon2 work that does not stop on interruption.
                    }
                }
            } finally {
                cleaned.countDown()
            }
        }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val cancelThread = Thread {
            handle.cancel()
            cancelReturned.countDown()
        }

        try {
            cancelThread.start()

            assertFalse(cancelReturned.await(250, TimeUnit.MILLISECONDS))
            release.countDown()
            assertTrue(cleaned.await(5, TimeUnit.SECONDS))
            assertTrue(cancelReturned.await(5, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            cancelThread.join(5_000)
            scheduler.close()
        }
    }

    @Test
    fun `cancelling queued pin work prevents it from running`() {
        val scheduler = SerialPinWorkScheduler()
        val firstStarted = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val firstCompleted = CountDownLatch(1)
        val secondRan = CountDownLatch(1)
        val thirdRan = CountDownLatch(1)

        try {
            scheduler.execute {
                firstStarted.countDown()
                try {
                    releaseFirst.await()
                } finally {
                    firstCompleted.countDown()
                }
            }
            assertTrue(firstStarted.await(5, TimeUnit.SECONDS))

            val queued = scheduler.execute {
                secondRan.countDown()
            }
            queued.cancel()

            releaseFirst.countDown()
            assertTrue(firstCompleted.await(5, TimeUnit.SECONDS))
            assertFalse(secondRan.await(250, TimeUnit.MILLISECONDS))

            scheduler.execute {
                thirdRan.countDown()
            }
            assertTrue(thirdRan.await(5, TimeUnit.SECONDS))
        } finally {
            releaseFirst.countDown()
            scheduler.close()
        }
    }

    @Test
    fun `closing scheduler interrupts active work and rejects future work`() {
        val scheduler = SerialPinWorkScheduler()
        val started = CountDownLatch(1)
        val interrupted = CountDownLatch(1)

        scheduler.execute {
            started.countDown()
            try {
                CountDownLatch(1).await()
            } catch (_: InterruptedException) {
                interrupted.countDown()
            }
        }
        assertTrue(started.await(5, TimeUnit.SECONDS))

        scheduler.close()

        assertTrue(interrupted.await(5, TimeUnit.SECONDS))
        assertThrows(NativeSecurityException::class.java) {
            scheduler.execute {}
        }
    }
}
