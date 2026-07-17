package com.example.note_secret_search.security

internal open class SecurityKeyringTestFixture {
    protected val store = FakeSecurityEnvelopeStore()
    protected val legacy = FakeLegacySecurityDetector()
    protected val keys = FakeWrappingKeyRepository()
    protected val authenticator = FakeSystemAuthenticator()
    protected val random = FixedRandomSource()
    protected val pinThrottleStore = FakePinThrottleStore()
    protected val pinThrottleClock = FakePinThrottleClock()
    protected val capabilities = SystemAuthCapabilities(
        deviceCredentialAvailable = true,
        strongBiometricAvailable = true,
    )

    protected fun provisionApi29WithBiometric() {
        random.enqueue(ByteArray(16) { (it + 2).toByte() })
        random.enqueue(ByteArray(32) { it.toByte() })
        manager(apiLevel = 29).provisionWithSystemAuth(
            "Create keyring",
            RecordingNativeResult(),
        )
    }

    protected fun manager(
        apiLevel: Int,
        authCapabilities: SystemAuthCapabilities = capabilities,
    ): NativeKeyringManager {
        return NativeKeyringManager(
            apiLevel = apiLevel,
            envelopeStore = store,
            legacyDetector = legacy,
            wrappingKeys = keys,
            authenticator = authenticator,
            capabilities = { authCapabilities },
            random = random,
            pinKdfEngine = DeterministicPinKdfEngine(),
            pinWorker = ImmediatePinWorkScheduler(),
            pinThrottle = testPinAttemptThrottle(
                store = pinThrottleStore,
                clock = pinThrottleClock,
            ),
        )
    }

    protected fun hex(value: String): ByteArray {
        return value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
}
