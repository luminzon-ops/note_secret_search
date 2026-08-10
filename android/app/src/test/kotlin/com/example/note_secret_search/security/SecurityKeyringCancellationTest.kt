package com.example.note_secret_search.security

import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

internal class SecurityKeyringCancellationTest : SecurityKeyringTestFixture() {
    @Test
    fun `lock completes without returning key material`() {
        assertNull(manager(apiLevel = 30).lock())
    }

    @Test
    fun `lock cancels an in flight authentication before keys can be delivered`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val deferredAuthenticator = DeferredSystemAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = deferredAuthenticator,
            capabilities = { capabilities },
            random = random,
            pinThrottle = testPinAttemptThrottle(),
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)
        manager.lock()
        deferredAuthenticator.succeed()

        assertEquals(1, deferredAuthenticator.cancelCalls)
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertNull(result.value)
        assertNull(store.bytes)
    }

    @Test
    fun `lock clears pending master key and generated aliases without a callback`() {
        val masterKey = ByteArray(32) { (it + 1).toByte() }
        val referenceRandom = ReferenceRandomSource(
            ByteArray(16) { (it + 2).toByte() },
            masterKey,
        )
        val deferredAuthenticator = DeferredSystemAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = deferredAuthenticator,
            capabilities = { capabilities },
            random = referenceRandom,
            pinThrottle = testPinAttemptThrottle(),
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)
        manager.lock()

        assertTrue(masterKey.all { it == 0.toByte() })
        assertTrue(keys.keys.isEmpty())
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertNull(store.bytes)
    }

    @Test
    fun `lock cannot split keyset persistence from successful completion`() {
        val blockingStore = BlockingSecurityEnvelopeStore()
        val result = ConcurrentRecordingNativeResult<NativeUnlockMaterial>()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = blockingStore,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { capabilities },
            random = FixedRandomSource().apply {
                enqueue(ByteArray(16) { (it + 2).toByte() })
                enqueue(ByteArray(32) { it.toByte() })
            },
            pinThrottle = testPinAttemptThrottle(),
        )
        val executor = Executors.newFixedThreadPool(2)

        try {
            val provision = executor.submit {
                manager.provisionWithSystemAuth("Create keyring", result)
            }
            assertTrue(blockingStore.writeStarted.await(5, TimeUnit.SECONDS))
            val lock = executor.submit { manager.lock() }

            val completedWhileWriteBlocked =
                result.completed.await(500, TimeUnit.MILLISECONDS)
            blockingStore.allowWrite.countDown()
            provision.get(5, TimeUnit.SECONDS)
            lock.get(5, TimeUnit.SECONDS)

            assertFalse(completedWhileWriteBlocked)
            assertNull(result.error)
            assertNotNull(result.value)
            assertNotNull(blockingStore.bytes)
        } finally {
            blockingStore.allowWrite.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `locking an old prompt does not cancel a newly started operation`() {
        val blockingAuthenticator = BlockingGlobalCancelAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = blockingAuthenticator,
            capabilities = { capabilities },
            random = FixedRandomSource().apply {
                enqueue(ByteArray(16) { (it + 2).toByte() })
                enqueue(ByteArray(32) { it.toByte() })
                enqueue(ByteArray(16) { (it + 18).toByte() })
                enqueue(ByteArray(32) { (it + 32).toByte() })
            },
            pinThrottle = testPinAttemptThrottle(),
        )
        val first = ConcurrentRecordingNativeResult<NativeUnlockMaterial>()
        val second = ConcurrentRecordingNativeResult<NativeUnlockMaterial>()
        val executor = Executors.newFixedThreadPool(2)

        try {
            manager.provisionWithSystemAuth("First operation", first)
            val lock = executor.submit { manager.lock() }
            assertTrue(blockingAuthenticator.cancelStarted.await(5, TimeUnit.SECONDS))
            val startSecond = executor.submit {
                manager.provisionWithSystemAuth("Second operation", second)
            }
            assertTrue(
                blockingAuthenticator.secondAuthenticationStarted.await(
                    5,
                    TimeUnit.SECONDS,
                ),
            )

            blockingAuthenticator.allowCancel.countDown()
            startSecond.get(5, TimeUnit.SECONDS)
            lock.get(5, TimeUnit.SECONDS)

            assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, first.error?.code)
            assertNull(second.error)
            assertNull(second.value)
        } finally {
            blockingAuthenticator.allowCancel.countDown()
            manager.lock()
            executor.shutdownNow()
        }
    }

    @Test
    fun `late biometric cancellation after lock does not start credential fallback`() {
        provisionApi29WithBiometric()
        val deferredAuthenticator = DeferredSystemAuthenticator()
        val manager = NativeKeyringManager(
            apiLevel = 29,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = deferredAuthenticator,
            capabilities = { capabilities },
            random = random,
            pinThrottle = testPinAttemptThrottle(),
        )
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.unlockWithSystemAuth("Unlock", result)
        manager.lock()
        deferredAuthenticator.fail(NativeSecurityErrorCode.AUTH_CANCELLED)

        assertEquals(
            listOf(SystemAuthenticatorMode.BIOMETRIC),
            deferredAuthenticator.requests.map { it.mode },
        )
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
        assertNull(result.value)
    }

    @Test
    fun `closing keyring cancels pin work and rejects later operations`() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        val scheduler = RecordingPinWorkScheduler()
        val manager = NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { capabilities },
            random = random,
            pinWorker = scheduler,
            pinThrottle = testPinAttemptThrottle(),
        )
        manager.provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
        val pendingPin = "2468".toByteArray()
        val pending = RecordingNativeResult<Unit>()
        manager.configurePin("Configure fallback PIN", pendingPin, pending)

        manager.close()

        assertEquals(1, scheduler.cancelCalls)
        assertEquals(1, scheduler.closeCalls)
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, pending.error?.code)
        assertTrue(pendingPin.all { it == 0.toByte() })

        val laterPin = "1357".toByteArray()
        val later = RecordingNativeResult<Unit>()
        manager.configurePin("Configure another PIN", laterPin, later)

        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, later.error?.code)
        assertTrue(laterPin.all { it == 0.toByte() })
        assertEquals(1, scheduler.executeCalls)
    }
}

private class DeferredSystemAuthenticator : SystemAuthenticator {
    val requests = mutableListOf<SystemAuthRequest>()
    var cancelCalls = 0
    private val pending = mutableListOf<PendingAuthentication>()

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        requests += request
        pending += PendingAuthentication(request, terminal)
    }

    override fun cancel(operationId: Long) {
        cancelCalls += 1
    }

    fun succeed() {
        pending.last().let { authentication ->
            authentication.terminal.succeeded(authentication.request.cipher)
        }
    }

    fun fail(code: NativeSecurityErrorCode) {
        pending.last().terminal.failed(NativeSecurityException(code))
    }
}

private data class PendingAuthentication(
    val request: SystemAuthRequest,
    val terminal: AuthenticationTerminal,
)

private class ReferenceRandomSource(
    vararg values: ByteArray,
) : RandomSource {
    private val values = ArrayDeque(values.toList())

    override fun bytes(size: Int): ByteArray {
        return values.removeFirst().also { require(it.size == size) }
    }
}

private class BlockingSecurityEnvelopeStore : SecurityEnvelopeStore {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)

    @Volatile
    var bytes: ByteArray? = null

    override fun read(): ByteArray? = bytes?.clone()

    override fun write(value: ByteArray) {
        writeStarted.countDown()
        check(allowWrite.await(5, TimeUnit.SECONDS))
        bytes = value.clone()
    }
}

private class ConcurrentRecordingNativeResult<T> : NativeResult<T> {
    val completed = CountDownLatch(1)

    @Volatile
    var value: T? = null

    @Volatile
    var error: NativeSecurityException? = null

    override fun success(value: T) {
        this.value = value
        completed.countDown()
    }

    override fun error(error: NativeSecurityException) {
        this.error = error
        completed.countDown()
    }
}

private class BlockingGlobalCancelAuthenticator : SystemAuthenticator {
    val cancelStarted = CountDownLatch(1)
    val secondAuthenticationStarted = CountDownLatch(1)
    val allowCancel = CountDownLatch(1)
    private val pending = mutableListOf<PendingAuthentication>()

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        synchronized(pending) {
            pending += PendingAuthentication(request, terminal)
            if (pending.size == 2) {
                secondAuthenticationStarted.countDown()
            }
        }
    }

    override fun cancel(operationId: Long) {
        cancelStarted.countDown()
        check(allowCancel.await(5, TimeUnit.SECONDS))
        val authentication = synchronized(pending) {
            pending.single { it.request.operationId == operationId }
        }
        authentication.terminal.failed(
            NativeSecurityException(NativeSecurityErrorCode.AUTH_CANCELLED),
        )
    }
}

private class RecordingPinWorkScheduler : PinWorkScheduler {
    var executeCalls = 0
    var cancelCalls = 0
    var closeCalls = 0

    override fun execute(task: () -> Unit): PinWorkHandle {
        executeCalls += 1
        return PinWorkHandle {
            cancelCalls += 1
        }
    }

    override fun close() {
        closeCalls += 1
    }
}
