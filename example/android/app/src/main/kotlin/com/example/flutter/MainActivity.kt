package com.example.flutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "posthog_flutter_example")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "triggerNativeCrash" -> {
                        NativeCrashHelper().triggerCrash()
                        result.success(null)
                    }
                    "presentNativeScreen" -> {
                        startActivity(Intent(this, NativeScreenActivity::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
