package com.example.note_secret_search

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DeviceProfilerPlugin(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getProfile" -> result.success(buildProfile())
            else -> result.notImplemented()
        }
    }

    private fun buildProfile(): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memInfo)

        val totalRamMb = memInfo.totalMem / (1024 * 1024)
        val availableRamMb = memInfo.availMem / (1024 * 1024)

        val statFs = StatFs(Environment.getDataDirectory().absolutePath)
        val totalStorageMb = statFs.totalBytes / (1024 * 1024)
        val availableStorageMb = statFs.availableBytes / (1024 * 1024)

        val tier = when {
            totalRamMb >= 8192 -> "high"
            totalRamMb >= 4096 -> "mid"
            else -> "low"
        }

        return mapOf(
            "manufacturer" to safeBuildString { Build.MANUFACTURER },
            "model" to safeBuildString { Build.MODEL },
            "sdkInt" to safeBuildInt { Build.VERSION.SDK_INT },
            "release" to safeBuildString { Build.VERSION.RELEASE },
            "cpuAbi" to safeBuildString { Build.SUPPORTED_ABIS.firstOrNull() },
            "totalRamMb" to totalRamMb,
            "availableRamMb" to availableRamMb,
            "totalStorageMb" to totalStorageMb,
            "availableStorageMb" to availableStorageMb,
            "tier" to tier,
        )
    }

    private fun safeBuildString(block: () -> String?): String {
        return try {
            block() ?: "unknown"
        } catch (_: Throwable) {
            "unknown"
        }
    }

    private fun safeBuildInt(block: () -> Int): Int {
        return try {
            block()
        } catch (_: Throwable) {
            -1
        }
    }

    companion object {
        const val CHANNEL_NAME = "note_secret_search/device_profiler"
    }
}
