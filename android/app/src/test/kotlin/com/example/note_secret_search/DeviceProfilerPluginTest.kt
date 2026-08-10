package com.example.note_secret_search

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceProfilerPluginTest {
    @Test
    fun `getProfile returns complete device facts without readiness state`() {
        val plugin = DeviceProfilerPlugin(
            DeviceProfileReader {
                profile(
                    supportedAbis = listOf(
                        "arm64-v8a",
                        "armeabi-v7a",
                        "x86_64",
                        "x86",
                    ),
                )
            },
        )
        val result = DeviceProfilerRecordingResult()

        plugin.onMethodCall(MethodCall("getProfile", null), result)

        val value = result.successValue as Map<*, *>
        assertEquals("Huawei", value["manufacturer"])
        assertEquals("HUAWEI", value["brand"])
        assertEquals("SPN-AL00", value["model"])
        assertEquals("HWSPN", value["device"])
        assertEquals("SPN-AL00", value["product"])
        assertEquals(29, value["sdkInt"])
        assertEquals("10", value["release"])
        assertEquals(
            listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86"),
            value["supportedAbis"],
        )
        assertEquals("arm64-v8a", value["cpuAbi"])
        assertEquals(8192L, value["totalRamMb"])
        assertEquals(4096L, value["availableRamMb"])
        assertEquals(128000L, value["totalStorageMb"])
        assertEquals(64000L, value["availableStorageMb"])
        assertFalse(value.containsKey("tier"))
        assertFalse(value.containsKey("ready"))
        assertFalse(value.containsKey("enabled"))
        assertEquals(1, result.callbackCount)
    }

    @Test
    fun `getProfile preserves the complete supported ABI preference matrix`() {
        val matrix = listOf(
            listOf("arm64-v8a"),
            listOf("armeabi-v7a"),
            listOf("x86_64"),
            listOf("x86"),
            listOf("x86_64", "arm64-v8a", "armeabi-v7a", "x86"),
        )

        matrix.forEach { expectedAbis ->
            val plugin = DeviceProfilerPlugin(
                DeviceProfileReader { profile(supportedAbis = expectedAbis) },
            )
            val result = DeviceProfilerRecordingResult()

            plugin.onMethodCall(MethodCall("getProfile", null), result)

            val value = result.successValue as Map<*, *>
            assertEquals(expectedAbis, value["supportedAbis"])
            assertEquals(expectedAbis.first(), value["cpuAbi"])
        }
    }

    @Test
    fun `profile collection failure returns a stable platform error`() {
        val plugin = DeviceProfilerPlugin(
            DeviceProfileReader {
                throw IllegalStateException("/private/device/profile/details")
            },
        )
        val result = DeviceProfilerRecordingResult()

        plugin.onMethodCall(MethodCall("getProfile", null), result)

        assertNull(result.successValue)
        assertEquals("PROFILE_UNAVAILABLE", result.errorCode)
        assertEquals("Device profile unavailable.", result.errorMessage)
        assertNull(result.errorDetails)
        assertFalse(result.errorMessage.orEmpty().contains("/private/"))
        assertEquals(1, result.callbackCount)
    }

    @Test
    fun `unknown method remains not implemented`() {
        val plugin = DeviceProfilerPlugin(
            DeviceProfileReader { profile(supportedAbis = listOf("arm64-v8a")) },
        )
        val result = DeviceProfilerRecordingResult()

        plugin.onMethodCall(MethodCall("unknown", null), result)

        assertTrue(result.notImplemented)
        assertEquals(1, result.callbackCount)
    }

    private fun profile(supportedAbis: List<String>) = DeviceProfileSnapshot(
        manufacturer = "Huawei",
        brand = "HUAWEI",
        model = "SPN-AL00",
        device = "HWSPN",
        product = "SPN-AL00",
        sdkInt = 29,
        release = "10",
        supportedAbis = supportedAbis,
        totalRamMb = 8192,
        availableRamMb = 4096,
        totalStorageMb = 128000,
        availableStorageMb = 64000,
    )
}

private class DeviceProfilerRecordingResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Any? = null
    var notImplemented = false
    var callbackCount = 0

    override fun success(result: Any?) {
        callbackCount += 1
        successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        callbackCount += 1
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
    }

    override fun notImplemented() {
        callbackCount += 1
        notImplemented = true
    }
}
