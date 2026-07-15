package com.example.note_secret_search.security

import java.security.Key
import java.util.ArrayDeque
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal class FakeSecurityEnvelopeStore(
    var bytes: ByteArray? = null,
    var failWrites: Boolean = false,
    var failOnWrite: Int? = null,
) : SecurityEnvelopeStore {
    var writes = 0

    override fun read(): ByteArray? = bytes?.clone()

    override fun write(value: ByteArray) {
        writes += 1
        if (failWrites || failOnWrite == writes) {
            throw NativeSecurityException(
                NativeSecurityErrorCode.SECURE_STORAGE_UNAVAILABLE,
            )
        }
        bytes = value.clone()
    }
}

internal class FakeLegacySecurityDetector(
    var legacyPasswordPresent: Boolean = false,
) : LegacySecurityDetector {
    override fun hasLegacyPassword(): Boolean = legacyPasswordPresent
}

internal class FakeWrappingKeyRepository(
    private val generatedLevel: KeySecurityLevel = KeySecurityLevel.TEE,
    private val loadedLevel: KeySecurityLevel = generatedLevel,
) : WrappingKeyRepository {
    val keys = linkedMapOf<String, Key>()
    var createCalls = 0
    var deleteCalls = 0
    var invalidated = false
    var failPolicy: WrappingKeyPolicy? = null

    override fun create(alias: String, policy: WrappingKeyPolicy): WrappingKeyHandle {
        createCalls += 1
        if (policy == failPolicy) {
            throw KeystoreOperationFailure()
        }
        val key = SecretKeySpec(ByteArray(32) { (it + createCalls).toByte() }, "AES")
        keys[alias] = key
        return TestWrappingKeyHandle(alias, generatedLevel, key) { invalidated }
    }

    override fun load(alias: String): WrappingKeyHandle? {
        val key = keys[alias] ?: return null
        return TestWrappingKeyHandle(alias, loadedLevel, key) { invalidated }
    }

    override fun delete(alias: String) {
        deleteCalls += 1
        keys.remove(alias)
    }
}

internal class TestWrappingKeyHandle(
    override val alias: String,
    override val securityLevel: KeySecurityLevel,
    private val key: Key,
    private val invalidated: () -> Boolean = { false },
) : WrappingKeyHandle {
    override fun encryptionCipher(): Cipher {
        checkValid()
        return Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, key)
        }
    }

    override fun decryptionCipher(nonce: ByteArray): Cipher {
        checkValid()
        return Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
        }
    }

    private fun checkValid() {
        if (invalidated()) {
            throw WrappingKeyInvalidatedException()
        }
    }
}

internal class FakeSystemAuthenticator : SystemAuthenticator {
    private val outcomes = ArrayDeque<AuthOutcome>()
    val requests = mutableListOf<SystemAuthRequest>()

    fun enqueue(outcome: AuthOutcome) {
        outcomes.addLast(outcome)
    }

    override fun authenticate(
        request: SystemAuthRequest,
        terminal: AuthenticationTerminal,
    ) {
        requests += request
        val outcome = if (outcomes.isEmpty()) AuthOutcome.Success else outcomes.removeFirst()
        when (outcome) {
            AuthOutcome.Success -> terminal.succeeded(request.cipher)
            is AuthOutcome.Error -> terminal.failed(
                NativeSecurityException(outcome.code),
            )
            AuthOutcome.MismatchThenSuccess -> {
                AuthenticationResultDispatcher(terminal).onAuthenticationFailed()
                terminal.succeeded(request.cipher)
            }
        }
    }

    override fun cancel() {
    }
}

internal sealed interface AuthOutcome {
    data object Success : AuthOutcome
    data object MismatchThenSuccess : AuthOutcome
    data class Error(val code: NativeSecurityErrorCode) : AuthOutcome
}

internal class FixedRandomSource(
    private val values: ArrayDeque<ByteArray> = ArrayDeque(),
) : RandomSource {
    fun enqueue(value: ByteArray) {
        values.addLast(value.clone())
    }

    override fun bytes(size: Int): ByteArray {
        val value = if (values.isEmpty()) {
            ByteArray(size) { (it + 1).toByte() }
        } else {
            values.removeFirst()
        }
        require(value.size == size)
        return value.clone()
    }
}

internal class RecordingNativeResult<T> : NativeResult<T> {
    var value: T? = null
    var error: NativeSecurityException? = null

    override fun success(value: T) {
        this.value = value
    }

    override fun error(error: NativeSecurityException) {
        this.error = error
    }
}
