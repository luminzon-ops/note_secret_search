package com.example.note_secret_search

import android.os.Bundle
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var nativeSecurityPlugin: NativeSecurityPlugin
    private lateinit var recentTaskShieldView: FrameLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recentTaskShieldView = FrameLayout(this).apply {
            setBackgroundColor(0xFF101418.toInt())
            alpha = 0.98f
            visibility = android.view.View.GONE
        }
        addContentView(
            recentTaskShieldView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeSecurityPlugin = NativeSecurityPlugin(this, recentTaskShieldView)
        nativeSecurityPlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)
    }
}
