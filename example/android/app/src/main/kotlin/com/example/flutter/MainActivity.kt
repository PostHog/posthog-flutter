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
                        val captured = call.argument<Boolean>("capture") ?: true
                        startActivity(
                            Intent(this, NativeScreenActivity::class.java)
                                .putExtra("captured", captured),
                        )
                        result.success(null)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
}
