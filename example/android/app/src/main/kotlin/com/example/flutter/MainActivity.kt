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
                    // Crash on a background thread because Flutter wraps and
                    // swallows exceptions from the method channel handler as
                    // a PlatformException, preventing the app from actually crashing.
                    Thread {
                        NativeCrashHelper().triggerCrash()
                    }.start()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
