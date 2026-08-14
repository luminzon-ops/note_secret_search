package com.example.note_secret_search

import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var nativeSecurityPlugin: NativeSecurityPlugin
    private lateinit var embeddingRuntimePlugin: EmbeddingRuntimePlugin
    private lateinit var llmRuntimePlugin: LlmRuntimePlugin
    private lateinit var deviceProfilerPlugin: DeviceProfilerPlugin
    private val recentTaskShieldCoordinator = RecentTaskShieldCoordinator(
        create = {
            FrameLayout(this).apply {
                setBackgroundColor(0xFF101418.toInt())
                alpha = 0.98f
                contentDescription = RECENT_TASK_SHIELD_MARKER
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                visibility = View.GONE
            }
        },
        attach = { shield ->
            addContentView(
                shield,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        },
    )

    private val recentTaskShieldView: FrameLayout
        get() = recentTaskShieldCoordinator.shield()

    override fun onCreate(savedInstanceState: Bundle?) {
        recentTaskShieldView
        super.onCreate(savedInstanceState)
        recentTaskShieldCoordinator.attachIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeSecurityPlugin = NativeSecurityPlugin(this, recentTaskShieldView)
        nativeSecurityPlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

        embeddingRuntimePlugin = EmbeddingRuntimePlugin(this)
        embeddingRuntimePlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

        llmRuntimePlugin = LlmRuntimePlugin(this)
        llmRuntimePlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

        deviceProfilerPlugin = DeviceProfilerPlugin(this)
        val deviceProfilerChannel = io.flutter.plugin.common.MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeviceProfilerPlugin.CHANNEL_NAME,
        )
        deviceProfilerChannel.setMethodCallHandler(deviceProfilerPlugin)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (this::nativeSecurityPlugin.isInitialized) {
            nativeSecurityPlugin.onWindowFocusChanged(hasFocus)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (this::llmRuntimePlugin.isInitialized) {
            llmRuntimePlugin.detachFromEngine()
        }
        if (this::embeddingRuntimePlugin.isInitialized) {
            embeddingRuntimePlugin.detachFromEngine()
        }
        if (this::nativeSecurityPlugin.isInitialized) {
            nativeSecurityPlugin.detachFromEngine()
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        internal const val RECENT_TASK_SHIELD_MARKER = "NSS_PRIVACY_SHIELD_ACTIVE"
    }
}
