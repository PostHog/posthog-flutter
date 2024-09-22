package com.posthog.posthog_flutter

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.posthog.PostHog
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import com.posthog.internal.replay.RRFullSnapshotEvent
import com.posthog.internal.replay.RRStyle
import com.posthog.internal.replay.RRWireframe
import com.posthog.internal.replay.capture
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream

/** PosthogFlutterPlugin */
class PosthogFlutterPlugin : FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel

    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "posthog_flutter")

        context = flutterPluginBinding.applicationContext

        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {

        when (call.method) {

            "identify" -> {
                identify(call, result)
            }

            "capture" -> {
                capture(call, result)
            }

            "screen" -> {
                screen(call, result)
            }

            "alias" -> {
                alias(call, result)
            }

            "distinctId" -> {
                distinctId(result)
            }

            "reset" -> {
                reset(result)
            }

            "disable" -> {
                disable(result)
            }

            "enable" -> {
                enable(result)
            }

            "isFeatureEnabled" -> {
                isFeatureEnabled(call, result)
            }

            "reloadFeatureFlags" -> {
                reloadFeatureFlags(result)
            }

            "group" -> {
                group(call, result)
            }

            "getFeatureFlag" -> {
                getFeatureFlag(call, result)
            }

            "getFeatureFlagPayload" -> {
                getFeatureFlagPayload(call, result)
            }

            "register" -> {
                register(call, result)
            }

            "unregister" -> {
                unregister(call, result)
            }

            "debug" -> {
                debug(call, result)
            }

            "flush" -> {
                flush(result)
            }

            "initNativeSdk" -> {
                val configMap = call.arguments as? Map<String, Any>
                println()
                if (configMap != null) {
                    initPlugin(configMap)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Config map is null or invalid", null)
                }
            }

            "sendReplayScreenshot" -> {
                sendReplayScreenshot(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }

    }

    private fun initPlugin(configMap: Map<String, Any>) {
        val apiKey = configMap["apiKey"] as? String ?: ""
        val options = configMap["options"] as? Map<String, Any> ?: emptyMap()

        val captureNativeAppLifecycleEvents =
            options["captureNativeAppLifecycleEvents"] as? Boolean ?: false
        val enableSessionReplay = options["enableSessionReplay"] as? Boolean ?: false
        val sessionReplayConfigMap =
            options["sessionReplayConfig"] as? Map<String, Any> ?: emptyMap()

        val maskAllTextInputs = sessionReplayConfigMap["maskAllTextInputs"] as? Boolean ?: true
        val maskAllImages = sessionReplayConfigMap["maskAllImages"] as? Boolean ?: true
        val captureLog = sessionReplayConfigMap["captureLog"] as? Boolean ?: true
        val debouncerDelayMs =
            (sessionReplayConfigMap["androidDebouncerDelayMs"] as? Int ?: 500).toLong()

        val config = PostHogAndroidConfig(apiKey).apply {
            debug = false
            captureDeepLinks = false
            captureApplicationLifecycleEvents = captureNativeAppLifecycleEvents
            captureScreenViews = false
            sessionReplay = enableSessionReplay
            sessionReplayConfig.screenshot = true
            sessionReplayConfig.captureLogcat = captureLog
            sessionReplayConfig.debouncerDelayMs = debouncerDelayMs
            sessionReplayConfig.maskAllImages = maskAllImages
            sessionReplayConfig.maskAllTextInputs = maskAllTextInputs
        }

        PostHogAndroid.setup(context, config)
    }

    /*
    * TEMPORARY FUNCTION FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
    private fun sendReplayScreenshot(call: MethodCall, result: Result) {
        val imageBytes = call.argument<ByteArray>("imageBytes")
        if (imageBytes != null) {
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)

            val base64String = bitmapToBase64(bitmap)

            val wireframe = RRWireframe(
                id = System.identityHashCode(bitmap),
                x = 0,
                y = 0,
                width = bitmap.width,
                height = bitmap.height,
                type = "screenshot",
                base64 = base64String,
                style = RRStyle()
            )

            val snapshotEvent = RRFullSnapshotEvent(
                listOf(wireframe),
                initialOffsetTop = 0,
                initialOffsetLeft = 0,
                timestamp = System.currentTimeMillis()
            )

            listOf(snapshotEvent).capture()
            if (base64String != null) {
                Log.d("PostHog", base64String)
            }
        } else {
            result.error("INVALID_ARGUMENT", "Image bytes are null", null)
        }
    }

    private fun bitmapToBase64(bitmap: Bitmap): String? {
        ByteArrayOutputStream().use { byteArrayOutputStream ->
            bitmap.compress(
                Bitmap.CompressFormat.JPEG,
                30,
                byteArrayOutputStream
            )
            val byteArray = byteArrayOutputStream.toByteArray()
            return android.util.Base64.encodeToString(byteArray, android.util.Base64.NO_WRAP)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun getFeatureFlag(call: MethodCall, result: Result) {
        try {
            val featureFlagKey: String = call.argument("key")!!
            val flag = PostHog.getFeatureFlag(featureFlagKey)
            result.success(flag)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getFeatureFlagPayload(call: MethodCall, result: Result) {
        try {
            val featureFlagKey: String = call.argument("key")!!
            val flag = PostHog.getFeatureFlagPayload(featureFlagKey)
            result.success(flag)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun identify(call: MethodCall, result: Result) {
        try {
            val userId: String = call.argument("userId")!!
            val userProperties: Map<String, Any>? = call.argument("userProperties")
            val userPropertiesSetOnce: Map<String, Any>? = call.argument("userPropertiesSetOnce")
            PostHog.identify(userId, userProperties, userPropertiesSetOnce)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun capture(call: MethodCall, result: Result) {
        try {
            val eventName: String = call.argument("eventName")!!
            val properties: Map<String, Any>? = call.argument("properties")
            PostHog.capture(eventName, properties = properties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun screen(call: MethodCall, result: Result) {
        try {
            val screenName: String = call.argument("screenName")!!
            val properties: Map<String, Any>? = call.argument("properties")
            PostHog.screen(screenName, properties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun alias(call: MethodCall, result: Result) {
        try {
            val alias: String = call.argument("alias")!!
            PostHog.alias(alias)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun distinctId(result: Result) {
        try {
            val distinctId: String = PostHog.distinctId()
            result.success(distinctId)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reset(result: Result) {
        try {
            PostHog.reset()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun enable(result: Result) {
        try {
            PostHog.optIn()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun debug(call: MethodCall, result: Result) {
        try {
            val debug: Boolean = call.argument("debug")!!
            PostHog.debug(debug)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun disable(result: Result) {
        try {
            PostHog.optOut()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun isFeatureEnabled(call: MethodCall, result: Result) {
        try {
            val key: String = call.argument("key")!!
            val isEnabled = PostHog.isFeatureEnabled(key)
            result.success(isEnabled)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reloadFeatureFlags(result: Result) {
        try {
            PostHog.reloadFeatureFlags()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun group(call: MethodCall, result: Result) {
        try {
            val groupType: String = call.argument("groupType")!!
            val groupKey: String = call.argument("groupKey")!!
            val groupProperties: Map<String, Any>? = call.argument("groupProperties")
            PostHog.group(groupType, groupKey, groupProperties)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun register(call: MethodCall, result: Result) {
        try {
            val key: String = call.argument("key")!!
            val value: Any = call.argument("value")!!
            PostHog.register(key, value)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun unregister(call: MethodCall, result: Result) {
        try {
            val key: String = call.argument("key")!!
            PostHog.unregister(key)
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun flush(result: Result) {
        try {
            PostHog.flush()
            result.success(null)
        } catch (e: Throwable) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }
}
