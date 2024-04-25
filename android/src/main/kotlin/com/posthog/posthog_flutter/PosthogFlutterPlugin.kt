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

/** PosthogFlutterPlugin */
class PosthogFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "posthog_flutter")
        applicationContext = flutterPluginBinding.applicationContext
        initPlugin(applicationContext)
        channel.setMethodCallHandler(this)
    }

    private fun initPlugin(context: Context) {
        try {
            val ai = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
            val bundle = ai.metaData
            val apiKey = bundle.getString("com.posthog.posthog.API_KEY", null)
            if (apiKey.isNullOrEmpty()) {
                Log.e("PostHog", "com.posthog.posthog.API_KEY is missing!")
                return
            }
            val host = bundle.getString("com.posthog.posthog.POSTHOG_HOST", PostHogConfig.DEFAULT_HOST)
            val trackApplicationLifecycleEvents = bundle.getBoolean("com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS", false)
            val enableDebug = bundle.getBoolean("com.posthog.posthog.DEBUG", false)

            val config = PostHogAndroidConfig(apiKey, host).apply {
                captureScreenViews = false
                captureDeepLinks = false
                captureApplicationLifecycleEvents = trackApplicationLifecycleEvents
                debug = enableDebug
                sdkName = "posthog-flutter"
                sdkVersion = postHogVersion
            }
            PostHogAndroid.setup(applicationContext, config)

        } catch (e: Exception) {
            Log.e("PostHog", "initPlugin error: ${e.localizedMessage}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "identify" -> identify(call, result)
            "capture" -> capture(call, result)
            "screen" -> screen(call, result)
            "alias" -> alias(call, result)
            "distinctId" -> distinctId(result)
            "reset" -> reset(result)
            "disable" -> disable(result)
            "enable" -> enable(result)
            "debug" -> debug(call, result)
            "register" -> register(call, result)
            "unregister" -> unregister(call, result)
            "flush" -> flush(result)
            "isFeatureEnabled" -> isFeatureEnabled(call, result)
            "reloadFeatureFlags" -> reloadFeatureFlags(result)
            "group" -> group(call, result)
            "getFeatureFlag" -> getFeatureFlag(call, result)
            "getFeatureFlagPayload" -> getFeatureFlagPayload(call, result)
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: Result) {
        try {
            val apiKey: String = call.argument("apiKey") ?: return result.error("Invalid API Key", "API Key is null or empty", null)
            val host: String = call.argument("host") ?: return result.error("Invalid Host", "Host is null or empty", null)
            val trackLifecycleEvents: Boolean = call.argument("trackLifecycleEvents") ?: false
            val enableDebug: Boolean = call.argument("enableDebug") ?: false

            val config = PostHogAndroidConfig(apiKey, host).apply {
                captureApplicationLifecycleEvents = trackLifecycleEvents
                debug = enableDebug
                sdkName = "posthog-flutter"
                sdkVersion = postHogVersion
            }
            PostHogAndroid.setup(applicationContext, config)
            result.success(null)
        } catch (e: Exception) {
            result.error("ConfigurationError", "Failed to configure PostHog: ${e.localizedMessage}", null)
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
