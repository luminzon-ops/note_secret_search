package com.example.note_secret_search.security

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityKeyringConcurrencyTest {
    private val capabilities = SystemAuthCapabilities(
        deviceCredentialAvailable = true,
        strongBiometricAvailable = true,
    )

    @Test
    fun `lock cannot overtake alias creation and authentication start`() {
        val store = FakeSecurityEnvelopeStore()
        val delegateKeys = FakeWrappingKeyRepository()
        val keys = BlockingCreateWrappingKeyRepository(delegateKeys)
        val authenticator = OrderingSystemAuthenticator()
        val result = ConcurrentSecurityResult<NativeUnlockMaterial>()
        val manager = manager(store, keys, authenticator)
        val executor = Executors.newFixedThreadPool(2)
        val lockCompleted = CountDownLatch(1)

        try {
            val provision = executor.submit {
                manager.provisionWithSystemAuth("Create keyring", result)
            }
            assertTrue(keys.createStarted.await(5, TimeUnit.SECONDS))
            val lock = executor.submit {
                try {
                    manager.lock()
                } finally {
                    lockCompleted.countDown()
                }
            }

            val lockOvertookCreate = lockCompleted.await(250, TimeUnit.MILLISECONDS)
            keys.allowCreate.countDown()
            provision.get(5, TimeUnit.SECONDS)
            lock.get(5, TimeUnit.SECONDS)

            assertFalse(lockOvertookCreate)
            assertEquals(
                listOf("authenticate:1", "cancel:1"),
                authenticator.events,
            )
            assertTrue(delegateKeys.keys.isEmpty())
            assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
            assertNull(store.bytes)
        } finally {
            keys.allowCreate.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `lock cannot overtake alias loading and unlock authentication start`() {
        val store = FakeSecurityEnvelopeStore()
        val delegateKeys = FakeWrappingKeyRepository()
        provision(store, delegateKeys)
        val keys = BlockingLoadWrappingKeyRepository(delegateKeys)
        val authenticator = OrderingSystemAuthenticator()
        val result = ConcurrentSecurityResult<NativeUnlockMaterial>()
        val manager = manager(store, keys, authenticator)
        val executor = Executors.newFixedThreadPool(2)
        val lockCompleted = CountDownLatch(1)

        try {
            val unlock = executor.submit {
                manager.unlockWithSystemAuth("Unlock", result)
            }
            assertTrue(keys.loadStarted.await(5, TimeUnit.SECONDS))
            val lock = executor.submit {
                try {
                    manager.lock()
                } finally {
                    lockCompleted.countDown()
                }
            }

            val lockOvertookLoad = lockCompleted.await(250, TimeUnit.MILLISECONDS)
            keys.allowLoad.countDown()
            unlock.get(5, TimeUnit.SECONDS)
            lock.get(5, TimeUnit.SECONDS)

            assertFalse(lockOvertookLoad)
            assertEquals(
                listOf("authenticate:1", "cancel:1"),
                authenticator.events,
            )
            assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.error?.code)
            assertNull(result.value)
        } finally {
            keys.allowLoad.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `throwing success delegate cannot invalidate a committed keyset`() {
        val store = FakeSecurityEnvelopeStore()
        val keys = FakeWrappingKeyRepository()
        val authenticator = FakeSystemAuthenticator()
        val manager = manager(store, keys, authenticator)
        val throwingResult = ThrowingSuccessSecurityResult()

        manager.provisionWithSystemAuth("Create keyring", throwingResult)

        assertNotNull(store.bytes)
        assertTrue(keys.keys.isNotEmpty())
        assertEquals(SecurityStatus.LOCKED, manager.getSecurityState().status)
        assertTrue(
            throwingResult.delivered!!.databaseKey.all { it == 0.toByte() },
        )
        assertTrue(
            throwingResult.delivered!!.fieldKey.all { it == 0.toByte() },
        )

        val unlock = RecordingNativeResult<NativeUnlockMaterial>()
        manager.unlockWithSystemAuth("Unlock", unlock)
        assertNull(unlock.error)
        assertNotNull(unlock.value)
    }

    @Test
    fun `authenticator throw after success cannot invalidate a committed keyset`() {
        val store = FakeSecurityEnvelopeStore()
        val keys = FakeWrappingKeyRepository()
        val manager = manager(store, keys, SucceedThenThrowAuthenticator())
        val result = RecordingNativeResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        assertNotNull(store.bytes)
        assertTrue(keys.keys.isNotEmpty())
        assertEquals(SecurityStatus.LOCKED, manager.getSecurityState().status)

        val unlock = RecordingNativeResult<NativeUnlockMaterial>()
        manager(store, keys, FakeSystemAuthenticator())
            .unlockWithSystemAuth("Unlock", unlock)
        assertNull(unlock.error)
        assertNotNull(unlock.value)
    }

    @Test
    fun `optional biometric throw after success preserves both committed aliases`() {
        val store = FakeSecurityEnvelopeStore()
        val keys = FakeWrappingKeyRepository()
        val authenticator = SucceedThenThrowOnSecondAuthentication()
        val result = RecordingNativeResult<NativeUnlockMaterial>()
        val manager = NativeKeyringManager(
            apiLevel = 29,
            envelopeStore = store,
            legacyDetector = FakeLegacySecurityDetector(),
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { capabilities },
            random = FixedRandomSource(),
            pinThrottle = testPinAttemptThrottle(),
        )

        manager.provisionWithSystemAuth("Create keyring", result)

        assertNull(result.error)
        assertNotNull(result.value)
        assertEquals(2, keys.keys.size)
        assertEquals(
            listOf(EnvelopeKind.DEVICE_CREDENTIAL, EnvelopeKind.BIOMETRIC),
            SecurityKeysetCodec.decode(store.bytes!!).envelopes.map { it.kind },
        )
        assertEquals(SecurityStatus.LOCKED, manager.getSecurityState().status)

        val unlock = RecordingNativeResult<NativeUnlockMaterial>()
        manager(store, keys, FakeSystemAuthenticator())
            .unlockWithSystemAuth("Unlock", unlock)
        assertNull(unlock.error)
        assertNotNull(unlock.value)
    }

    @Test
    fun `throwing cancellation delegate cannot skip platform cancellation`() {
        val store = FakeSecurityEnvelopeStore()
        val keys = FakeWrappingKeyRepository()
        val authenticator = OrderingSystemAuthenticator()
        val manager = manager(store, keys, authenticator)
        val result = ThrowingErrorSecurityResult<NativeUnlockMaterial>()

        manager.provisionWithSystemAuth("Create keyring", result)

        assertNull(manager.lock())
        assertEquals(listOf("authenticate:1", "cancel:1"), authenticator.events)
        assertTrue(keys.keys.isEmpty())
        assertEquals(NativeSecurityErrorCode.AUTH_CANCELLED, result.delivered?.code)
    }

    @Test
    fun `security state waits for an in flight atomic keyset write`() {
        val store = BlockingWriteSecurityEnvelopeStore()
        val keys = FakeWrappingKeyRepository()
        val manager = manager(store, keys, FakeSystemAuthenticator())
        val provisionResult = ConcurrentSecurityResult<NativeUnlockMaterial>()
        val executor = Executors.newFixedThreadPool(2)
        val stateCompleted = CountDownLatch(1)

        try {
            val provision = executor.submit {
                manager.provisionWithSystemAuth("Create keyring", provisionResult)
            }
            assertTrue(store.writeStarted.await(5, TimeUnit.SECONDS))
            val state = executor.submit<NativeSecurityState> {
                try {
                    manager.getSecurityState()
                } finally {
                    stateCompleted.countDown()
                }
            }

            val readOvertookWrite = stateCompleted.await(250, TimeUnit.MILLISECONDS)
            store.allowWrite.countDown()
            provision.get(5, TimeUnit.SECONDS)

            assertFalse(readOvertookWrite)
            assertEquals(SecurityStatus.LOCKED, state.get(5, TimeUnit.SECONDS).status)
            assertNotNull(provisionResult.value)
        } finally {
            store.allowWrite.countDown()
            executor.shutdownNow()
        }
    }

    private fun provision(
        store: SecurityEnvelopeStore,
        keys: WrappingKeyRepository,
    ) {
        val result = RecordingNativeResult<NativeUnlockMaterial>()
        manager(store, keys, FakeSystemAuthenticator())
            .provisionWithSystemAuth("Create keyring", result)
        assertNull(result.error)
        assertNotNull(result.value)
    }

    private fun manager(
        store: SecurityEnvelopeStore,
        keys: WrappingKeyRepository,
        authenticator: SystemAuthenticator,
    ): NativeKeyringManager {
        return NativeKeyringManager(
            apiLevel = 30,
            envelopeStore = store,
            legacyDetector = FakeLegacySecurityDetector(),
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { capabilities },
            random = FixedRandomSource(),
            pinThrottle = testPinAttemptThrottle(),
        )
    }
}

private class BlockingCreateWrappingKeyRepository(
    private val delegate: WrappingKeyRepository,
) : WrappingKeyRepository {
    val createStarted = CountDownLatch(1)
    val allowCreate = CountDownLatch(1)

    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
    ): WrappingKeyHandle {
        createStarted.countDown()
        check(allowCreate.await(5, TimeUnit.SECONDS))
        return delegate.create(alias, policy)
    }

    override fun load(alias: String): WrappingKeyHandle? = delegate.load(alias)

    override fun delete(alias: String) = delegate.delete(alias)
}

private class BlockingLoadWrappingKeyRepository(
    private val delegate: WrappingKeyRepository,
) : WrappingKeyRepository {
    val loadStarted = CountDownLatch(1)
    val allowLoad = CountDownLatch(1)

    override fun create(
        alias: String,
        policy: WrappingKeyPolicy,
    ): WrappingKeyHandle = delegate.create(alias, policy)

    override fun load(alias: String): WrappingKeyHandle? {
        loadStarted.countDown()
        check(allowLoad.await(5, TimeUnit.SECONDS))
        return delegate.load(alias)
    }

    override fun delete(alias: String) = delegate.delete(alias)
}

private class OrderingSystemAuthenticator : SystemAuthenticator {
    val events = CopyOnWriteArrayList<String>()

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        events += "authenticate:${request.operationId}"
    }

    override fun cancel(operationId: Long) {
        events += "cancel:$operationId"
    }
}

private class SucceedThenThrowAuthenticator : SystemAuthenticator {
    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        terminal.succeeded(request.cipher)
        throw IllegalStateException("authenticator failed after callback")
    }

    override fun cancel(operationId: Long) {
    }
}

private class SucceedThenThrowOnSecondAuthentication : SystemAuthenticator {
    private var calls = 0

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        calls += 1
        terminal.succeeded(request.cipher)
        if (calls == 2) {
            throw IllegalStateException("optional authenticator failed after callback")
        }
    }

    override fun cancel(operationId: Long) {
    }
}

private class ConcurrentSecurityResult<T> : NativeResult<T> {
    @Volatile
    var value: T? = null

    @Volatile
    var error: NativeSecurityException? = null

    override fun success(value: T) {
        this.value = value
    }

    override fun error(error: NativeSecurityException) {
        this.error = error
    }
}

private class ThrowingSuccessSecurityResult : NativeResult<NativeUnlockMaterial> {
    var delivered: NativeUnlockMaterial? = null

    override fun success(value: NativeUnlockMaterial) {
        delivered = value
        throw IllegalStateException("transport closed")
    }

    override fun error(error: NativeSecurityException) {
    }
}

private class ThrowingErrorSecurityResult<T> : NativeResult<T> {
    var delivered: NativeSecurityException? = null

    override fun success(value: T) {
    }

    override fun error(error: NativeSecurityException) {
        delivered = error
        throw IllegalStateException("transport closed")
    }
}

private class BlockingWriteSecurityEnvelopeStore : SecurityEnvelopeStore {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)

    @Volatile
    private var bytes: ByteArray? = null

    override fun read(): ByteArray? = bytes?.clone()

    override fun write(value: ByteArray) {
        writeStarted.countDown()
        check(allowWrite.await(5, TimeUnit.SECONDS))
        bytes = value.clone()
    }
}
