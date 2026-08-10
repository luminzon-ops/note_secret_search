package com.example.note_secret_search.security

import com.lambdapioneer.argon2kt.Argon2Kt
import com.lambdapioneer.argon2kt.Argon2KtResult
import com.lambdapioneer.argon2kt.Argon2Mode
import com.lambdapioneer.argon2kt.Argon2Version
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.FutureTask
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal interface PinKdfEngine {
    fun derive(
        password: ByteArray,
        salt: ByteArray,
        iterations: Int,
        memoryKiB: Int,
        parallelism: Int,
        outputBytes: Int,
    ): ByteArray
}

internal class Argon2KtPinKdfEngine(
    private val createArgon2: () -> Argon2Kt = ::Argon2Kt,
) : PinKdfEngine {
    private val argon2: Argon2Kt by lazy(createArgon2)

    override fun derive(
        password: ByteArray,
        salt: ByteArray,
        iterations: Int,
        memoryKiB: Int,
        parallelism: Int,
        outputBytes: Int,
    ): ByteArray {
        val result = argon2.hash(
            Argon2Mode.ARGON2_ID,
            password,
            salt,
            iterations,
            memoryKiB,
            parallelism,
            outputBytes,
            Argon2Version.V13,
        )
        return copyRawHashAndZeroize(result)
    }
}

internal fun copyRawHashAndZeroize(result: Argon2KtResult): ByteArray {
    return try {
        result.rawHashAsByteArray()
    } finally {
        zeroize(result.rawHash)
        zeroize(result.encodedOutput)
    }
}

private fun zeroize(buffer: ByteBuffer) {
    val writable = buffer.duplicate()
    writable.clear()
    while (writable.hasRemaining()) {
        writable.put(0.toByte())
    }
}

internal fun interface PinWorkHandle {
    fun cancel()
}

internal interface PinWorkScheduler : AutoCloseable {
    fun execute(task: () -> Unit): PinWorkHandle

    override fun close()
}

internal class SerialPinWorkScheduler : PinWorkScheduler {
    private val executor = ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(1),
        { task ->
            Thread(task, "note-secret-search-pin-kdf").apply {
                isDaemon = true
            }
        },
        ThreadPoolExecutor.AbortPolicy(),
    )

    override fun execute(task: () -> Unit): PinWorkHandle {
        val started = AtomicBoolean(false)
        val completed = CountDownLatch(1)
        val future = FutureTask<Unit> {
            started.set(true)
            try {
                task()
                Unit
            } finally {
                completed.countDown()
            }
        }
        try {
            executor.execute(future)
        } catch (error: RejectedExecutionException) {
            future.cancel(true)
            completed.countDown()
            throw NativeSecurityException(
                if (executor.isShutdown) {
                    NativeSecurityErrorCode.AUTH_CANCELLED
                } else {
                    NativeSecurityErrorCode.BUSY
                },
                error,
            )
        }
        return PinWorkHandle {
            val cancelled = future.cancel(true)
            if (cancelled && !started.get()) {
                completed.countDown()
            }
            executor.purge()
            completed.awaitUninterruptibly()
        }
    }

    override fun close() {
        executor.shutdownNow().forEach { pending ->
            (pending as? FutureTask<*>)?.cancel(true)
        }
        executor.purge()
        executor.awaitTerminationUninterruptibly()
    }
}

private fun CountDownLatch.awaitUninterruptibly() {
    var interrupted = false
    while (count > 0) {
        try {
            await()
        } catch (_: InterruptedException) {
            interrupted = true
        }
    }
    if (interrupted) {
        Thread.currentThread().interrupt()
    }
}

private fun ThreadPoolExecutor.awaitTerminationUninterruptibly() {
    var interrupted = false
    while (!isTerminated) {
        try {
            awaitTermination(Long.MAX_VALUE, TimeUnit.NANOSECONDS)
        } catch (_: InterruptedException) {
            interrupted = true
        }
    }
    if (interrupted) {
        Thread.currentThread().interrupt()
    }
}

internal class PinKeyDeriver(
    private val engine: PinKdfEngine,
) {
    fun derive(
        pin: ByteArray,
        salt: ByteArray,
    ): ByteArray {
        try {
            if (pin.isEmpty() || salt.size != SALT_BYTES) {
                throw NativeSecurityException(
                    NativeSecurityErrorCode.INVALID_ARGUMENT,
                )
            }
            val key = engine.derive(
                password = pin,
                salt = salt,
                iterations = ITERATIONS,
                memoryKiB = MEMORY_KIB,
                parallelism = PARALLELISM,
                outputBytes = OUTPUT_BYTES,
            )
            if (key.size != OUTPUT_BYTES) {
                key.fill(0)
                throw NativeSecurityException(
                    NativeSecurityErrorCode.INTERNAL_ERROR,
                )
            }
            return key
        } finally {
            pin.fill(0)
        }
    }

    companion object {
        const val MEMORY_KIB = 65_536
        const val ITERATIONS = 3
        const val PARALLELISM = 1
        const val SALT_BYTES = 16
        const val OUTPUT_BYTES = 32
    }
}
