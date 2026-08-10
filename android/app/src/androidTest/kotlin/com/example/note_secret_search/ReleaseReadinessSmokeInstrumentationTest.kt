package com.example.note_secret_search

import android.os.Build
import android.security.NetworkSecurityPolicy
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReleaseReadinessSmokeInstrumentationTest {
    @Test
    fun packageMetadataAndCleartextPolicyMatchReleaseContract() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val applicationInfo = requireNotNull(packageInfo.applicationInfo)

        assertEquals("com.example.note_secret_search", context.packageName)
        assertEquals(34, applicationInfo.targetSdkVersion)
        assertTrue(Build.VERSION.SDK_INT >= 24)
        assertFalse(
            NetworkSecurityPolicy.getInstance()
                .isCleartextTrafficPermitted("example.com"),
        )
    }
}
