package com.example.note_secret_search.security

import android.app.KeyguardManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidKeystoreWrappingKeyInstrumentationTest {
    private lateinit var alias: String
    private lateinit var wrappingKeys: WrappingKeyRepository

    @Before
    fun setUp() {
        alias = "nss-instrumentation-wrapping-key-${UUID.randomUUID()}"
        wrappingKeys = AndroidWrappingKeyRepository(
            apiLevel = Build.VERSION.SDK_INT,
            backend = AndroidKeystoreWrappingKeyBackend(),
        )
        wrappingKeys.delete(alias)
    }

    @After
    fun tearDown() {
        if (::wrappingKeys.isInitialized && ::alias.isInitialized) {
            wrappingKeys.delete(alias)
        }
    }

    @Test
    fun wrappingKeyCanBeCreatedLoadedAndDeleted() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        assertTrue(
            "The device must have a secure lock-screen credential.",
            keyguard?.isDeviceSecure == true,
        )

        val created = wrappingKeys.create(
            alias = alias,
            policy = WrappingKeyPolicy.DEVICE_CREDENTIAL_WINDOW,
        )
        assertEquals(alias, created.alias)

        val loaded = wrappingKeys.load(alias)
        assertNotNull("Expected the wrapping key to persist in Android Keystore.", loaded)
        assertEquals(alias, loaded?.alias)

        wrappingKeys.delete(alias)

        assertNull(wrappingKeys.load(alias))
    }
}
