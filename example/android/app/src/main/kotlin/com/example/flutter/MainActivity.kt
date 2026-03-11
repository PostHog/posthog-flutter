package com.example.flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "posthog_flutter_example")
            .setMethodCallHandler { call, result ->
                if (call.method == "triggerNativeCrash") {
                    // Trigger a native crash by throwing an unhandled exception
                    throw RuntimeException("Test native crash from PostHog Flutter example")
                } else {
                    result.notImplemented()
                }
            }
    }
}
