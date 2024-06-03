package com.posthog.posthog_flutter

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.posthog.PostHog
import com.posthog.PostHogConfig
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/** PosthogFlutterPlugin */
class PosthogFlutterPlugin : FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "posthog_flutter")

        initPlugin(flutterPluginBinding.applicationContext)

        channel.setMethodCallHandler(this)
    }

    private val isLoaded = MutableStateFlow(false);

    private fun initPlugin(applicationContext: Context) {
        try {
            // TODO: replace deprecated method API 33
            val ai = applicationContext.packageManager.getApplicationInfo(applicationContext.packageName, PackageManager.GET_META_DATA)
            val bundle = ai.metaData
            val apiKey = bundle.getString("com.posthog.posthog.API_KEY", null)

            if (apiKey.isNullOrEmpty()) {
                Log.e("PostHog", "com.posthog.posthog.API_KEY is missing!")
                return
            }

            val host = bundle.getString("com.posthog.posthog.POSTHOG_HOST", PostHogConfig.DEFAULT_HOST)
            val trackApplicationLifecycleEvents = bundle.getBoolean("com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS", false)
            val enableDebug = bundle.getBoolean("com.posthog.posthog.DEBUG", false)

            // Init PostHog
            val config = PostHogAndroidConfig(apiKey, host).apply {
                captureScreenViews = false
                captureDeepLinks = false
                captureApplicationLifecycleEvents = trackApplicationLifecycleEvents
                debug = enableDebug
                sdkName = "posthog-flutter"
                sdkVersion = postHogVersion
                onFeatureFlags = PostHogOnFeatureFlags {
                    isLoaded.value = true;
                }
            }
            PostHogAndroid.setup(applicationContext, config)

        } catch (e: Throwable) {
            e.localizedMessage?.let { Log.e("PostHog", "initPlugin error: $it") }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {

        when (call.method) {
            "identify" -> identify(call, result)
            "capture" -> capture(call, result)
            "screen" -> screen(call, result)
            "alias" -> alias(call, result)
            "distinctId" -> distinctId(result)
            "reset" -> reset(result)
            "disable" -> disable(result)
            "enable" -> enable(result)
            "isFeatureEnabled" -> isFeatureEnabled(call, result)
            "reloadFeatureFlags" -> reloadFeatureFlags(result)
            "group" -> group(call, result)
            "getFeatureFlag" -> getFeatureFlag(call, result)
            "getFeatureFlagPayload" -> getFeatureFlagPayload(call, result)
            "register" -> register(call, result)
            "unregister" -> unregister(call, result)
            "debug" -> debug(call, result)
            "flush" -> flush(result)
            "awaitFeatureFlagsLoaded" -> awaitFeatureFlagsLoaded(result)
            else -> result.notImplemented()
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

    private fun awaitFeatureFlagsLoaded(result: Result){
        try {
            GlobalScope.launch {
                isLoaded.collect { isLoaded ->
                    if(isLoaded){
                        result.success()
                    }
                }
            }
        } catch (error: Throwable){
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
