package com.example.posthog_flutter

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.posthog.PostHog
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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

    private fun initPlugin(applicationContext: Context) {
        try {
            val ai = applicationContext.packageManager.getApplicationInfo(applicationContext.packageName, PackageManager.GET_META_DATA)
            val bundle = ai.metaData
            val apiKey = bundle.getString("com.posthog.posthog.API_KEY", "")
            val posthogHost = bundle.getString("com.posthog.posthog.POSTHOG_HOST", "")
            val trackApplicationLifecycleEvents = bundle.getBoolean("com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS", false)
            val enableDebug = bundle.getBoolean("com.posthog.posthog.DEBUG", false)

            // Init PostHog
            val config = PostHogAndroidConfig(apiKey, posthogHost).apply {
                captureScreenViews = false
                captureDeepLinks = false
                captureApplicationLifecycleEvents = trackApplicationLifecycleEvents
                debug = enableDebug
            }
            PostHogAndroid.setup(applicationContext, config)

        } catch (e: Exception) {
            e.localizedMessage?.let { Log.e("initPlugin", it) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {

        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }

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

            "getDistinctId" -> {
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

            "getFeatureFlagAndPayload" -> {
                getFeatureFlagAndPayload(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }

    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun getFeatureFlag(call: MethodCall, result: Result) {
        try {
            val featureFlagKey: String? = call.argument("key")
            val value: Any? = PostHog.getFeatureFlag(featureFlagKey!!)
            result.success(value)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getFeatureFlagPayload(call: MethodCall, result: Result) {
        try {
            val featureFlagKey: String? = call.argument("key")
            val value: Any? = PostHog.getFeatureFlagPayload(featureFlagKey!!)
            result.success(value)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun getFeatureFlagAndPayload(call: MethodCall, result: Result) {
        try {
            val featureFlagKey: String? = call.argument("key")
            val status: Any? = PostHog.getFeatureFlag(featureFlagKey!!)
            val payload: Any? = PostHog.getFeatureFlagPayload(featureFlagKey)
            val featureAndPayload = mutableMapOf<String, Any?>()

            when (status) {
                null -> {
                    featureAndPayload["isEnabled"] = false
                }

                is String -> {
                    featureAndPayload["isEnabled"] = true
                    featureAndPayload["variant"] = status
                }

                else -> {
                    featureAndPayload["isEnabled"] = status
                }
            }
            featureAndPayload["data"] = payload

            result.success(featureAndPayload)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun identify(call: MethodCall, result: Result) {
        try {
            val userId: String? = call.argument("userId")
            val propertiesData: HashMap<String, Any>? = call.argument("properties")
            val optionsData: HashMap<String, Any>? = call.argument("options")
            PostHog.identify(userId!!, propertiesData, optionsData)
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun capture(call: MethodCall, result: Result) {
        try {
            val eventName: String? = call.argument("eventName")
            val distinctId: String? = call.argument("distinctId")
            val propertiesData: HashMap<String, Any>? = call.argument("properties")
            val optionsData: HashMap<String, Any>? = call.argument("options")
            PostHog.capture(eventName!!, distinctId, propertiesData, optionsData)
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun screen(call: MethodCall, result: Result) {
        try {
            val screenName: String? = call.argument("screenName")
            val propertiesData: HashMap<String, Any>? = call.argument("properties")
            PostHog.screen(screenName!!, propertiesData)
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun alias(call: MethodCall, result: Result) {
        try {
            val alias: String? = call.argument("alias")
            PostHog.alias(alias!!)
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun distinctId(result: Result) {
        try {
            val anonymousId: String = PostHog.distinctId()
            result.success(anonymousId)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reset(result: Result) {
        try {
            PostHog.reset()
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    // There is no enable method at this time for PostHog on Android.
    // Instead, we use optOut as a proxy to achieve the same result.
    private fun enable(result: Result) {
        try {
            PostHog.optIn()
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    // There is no disable method at this time for PostHog on Android.
    // Instead, we use optOut as a proxy to achieve the same result.
    private fun disable(result: Result) {
        try {
            PostHog.optOut()
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun isFeatureEnabled(call: MethodCall, result: Result) {
        try {
            val key: String? = call.argument("key")
            val isEnabled: Boolean = PostHog.isFeatureEnabled(key!!)
            result.success(isEnabled)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun reloadFeatureFlags(result: Result) {
        try {
            PostHog.reloadFeatureFlags()
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }

    private fun group(call: MethodCall, result: Result) {
        try {
            val groupType: String? = call.argument("groupType")
            val groupKey: String? = call.argument("groupKey")
            val propertiesData: HashMap<String, Any>? = call.argument("groupProperties")
            PostHog.group(groupType!!, groupKey!!, propertiesData)
            result.success(true)
        } catch (e: Exception) {
            result.error("PosthogFlutterException", e.localizedMessage, null)
        }
    }


}
