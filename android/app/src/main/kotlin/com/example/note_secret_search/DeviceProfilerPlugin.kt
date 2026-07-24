package com.example.note_secret_search

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal data class DeviceProfileSnapshot(
    val manufacturer: String,
    val brand: String,
    val model: String,
    val device: String,
    val product: String,
    val sdkInt: Int,
    val release: String,
    val supportedAbis: List<String>,
    val totalRamMb: Long,
    val availableRamMb: Long,
    val totalStorageMb: Long,
    val availableStorageMb: Long,
) {
    fun toChannelMap(): Map<String, Any> {
        val abis = supportedAbis
            .map(String::trim)
            .filter(String::isNotEmpty)
            .distinct()
        return linkedMapOf(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "model" to model,
            "device" to device,
            "product" to product,
            "sdkInt" to sdkInt,
            "release" to release,
            "supportedAbis" to abis,
            // Kept for older Dart callers; recommendation is derived in Dart.
            "cpuAbi" to (abis.firstOrNull() ?: "unknown"),
            "totalRamMb" to totalRamMb.coerceAtLeast(0),
            "availableRamMb" to availableRamMb.coerceAtLeast(0),
            "totalStorageMb" to totalStorageMb.coerceAtLeast(0),
            "availableStorageMb" to availableStorageMb.coerceAtLeast(0),
        )
    }
}

internal fun interface DeviceProfileReader {
    fun read(): DeviceProfileSnapshot
}

class DeviceProfilerPlugin internal constructor(
    private val profileReader: DeviceProfileReader,
) : MethodChannel.MethodCallHandler {
    constructor(context: Context) : this(AndroidDeviceProfileReader(context))

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getProfile" -> {
                try {
                    result.success(profileReader.read().toChannelMap())
                } catch (_: Exception) {
                    result.error(
                        "PROFILE_UNAVAILABLE",
                        "Device profile unavailable.",
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL_NAME = "note_secret_search/device_profiler"
    }
}

private class AndroidDeviceProfileReader(
    private val context: Context,
) : DeviceProfileReader {
    override fun read(): DeviceProfileSnapshot {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: throw IllegalStateException("activity_manager_unavailable")
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        val statFs = StatFs(Environment.getDataDirectory().absolutePath)
        return DeviceProfileSnapshot(
            manufacturer = safeBuildString { Build.MANUFACTURER },
            brand = safeBuildString { Build.BRAND },
            model = safeBuildString { Build.MODEL },
            device = safeBuildString { Build.DEVICE },
            product = safeBuildString { Build.PRODUCT },
            sdkInt = safeBuildInt { Build.VERSION.SDK_INT },
            release = safeBuildString { Build.VERSION.RELEASE },
            supportedAbis = safeBuildAbis(),
            totalRamMb = toMebibytes(memInfo.totalMem),
            availableRamMb = toMebibytes(memInfo.availMem),
            totalStorageMb = toMebibytes(statFs.totalBytes),
            availableStorageMb = toMebibytes(statFs.availableBytes),
        )
    }

    private fun safeBuildAbis(): List<String> {
        return try {
            Build.SUPPORTED_ABIS
                .asSequence()
                .map(String::trim)
                .filter(String::isNotEmpty)
                .distinct()
                .toList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun safeBuildString(block: () -> String?): String {
        return try {
            block()?.trim()?.takeIf { it.isNotEmpty() } ?: "unknown"
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun safeBuildInt(block: () -> Int): Int {
        return try {
            block()
        } catch (_: Exception) {
            -1
        }
    }

    private fun toMebibytes(bytes: Long): Long {
        return (bytes / BYTES_PER_MEBIBYTE).coerceAtLeast(0)
    }

    companion object {
        private const val BYTES_PER_MEBIBYTE = 1024L * 1024L
    }
}
