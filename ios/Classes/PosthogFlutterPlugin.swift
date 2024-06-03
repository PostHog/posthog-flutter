import PostHog
#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif

public class PosthogFlutterPlugin: NSObject, FlutterPlugin {

    let isLoadedSubject = CurrentValueSubject<Bool, Error>(false)

    public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let channel = FlutterMethodChannel(name: "posthog_flutter", binaryMessenger: registrar.messenger())
#elseif os(macOS)
        let channel = FlutterMethodChannel(name: "posthog_flutter", binaryMessenger: registrar.messenger)
#endif
        let instance = PosthogFlutterPlugin()
        initPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public static func initPlugin() {
        // Initialise PostHog
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.API_KEY") as? String ?? ""

        if apiKey.isEmpty {
            print("[PostHog] com.posthog.posthog.API_KEY is missing!")
            return
        }

        let host = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.POSTHOG_HOST") as? String ?? PostHogConfig.defaultHost
        let postHogCaptureLifecyleEvents = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS") as? Bool ?? false
        let postHogDebug = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.DEBUG") as? Bool ?? false

        let config = PostHogConfig(
            apiKey: apiKey,
            host: host
        )
        config.captureApplicationLifecycleEvents = postHogCaptureLifecyleEvents
        config.debug = postHogDebug
        config.captureScreenViews = false
        
        // Update SDK name and version
         postHogSdkName = "posthog-flutter"
         postHogVersion = postHogFlutterVersion
        
        NotificationCenter.default.addObserver(forName: PostHogSDK.didReceiveFeatureFlags, object: nil, queue: nil)  { (notification) in
            isLoadedSubject.send(true)
        }
        PostHogSDK.shared.setup(config)
        //
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getFeatureFlag":
            getFeatureFlag(call, result: result)
        case "isFeatureEnabled":
            isFeatureEnabled(call, result: result)
        case "getFeatureFlagPayload":
            getFeatureFlagPayload(call, result: result)
        case "identify":
            identify(call, result: result)
        case "capture":
            capture(call, result: result)
        case "screen":
            screen(call, result: result)
        case "alias":
            alias(call, result: result)
        case "distinctId":
            distinctId(result)
        case "reset":
            reset(result)
        case "enable":
            enable(result)
        case "disable":
            disable(result)
        case "debug":
            debug(call, result: result)
        case "reloadFeatureFlags":
            reloadFeatureFlags(result)
        case "group":
            group(call, result: result)
        case "register":
            register(call, result: result)
        case "unregister":
            unregister(call, result: result)
        case "flush":
            flush(result)
        case "awaitFeatureFlagsLoaded":
            awaitFeatureFlagsLoaded(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getFeatureFlag(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.getFeatureFlag(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func isFeatureEnabled(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.isFeatureEnabled(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func getFeatureFlagPayload(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String
        {
            let value = PostHogSDK.shared.getFeatureFlagPayload(featureFlagKey)
            result(value)
        } else {
            _badArgumentError(result)
        }
    }

    private func identify(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let userId = args["userId"] as? String
        {
            let userProperties = args["userProperties"] as? [String: Any]
            let userPropertiesSetOnce = args["userPropertiesSetOnce"] as? [String: Any]

            PostHogSDK.shared.identify(
                userId,
                userProperties: userProperties,
                userPropertiesSetOnce: userPropertiesSetOnce
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func capture(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let eventName = args["eventName"] as? String
        {
            let properties = args["properties"] as? [String: Any]
            PostHogSDK.shared.capture(
                eventName,
                properties: properties
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func screen(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let screenName = args["screenName"] as? String
        {
            let properties = args["properties"] as? [String: Any]
            PostHogSDK.shared.screen(
                screenName,
                properties: properties
            )
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func alias(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let alias = args["alias"] as? String
        {
            PostHogSDK.shared.alias(alias)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func distinctId(_ result: @escaping FlutterResult) {
        let val = PostHogSDK.shared.getDistinctId()
        result(val)
    }

    private func reset(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.reset()
        result(nil)
    }

    private func enable(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.optIn()
        result(nil)
    }

    private func disable(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.optOut()
        result(nil)
    }

    private func debug(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let debug = args["debug"] as? Bool
        {
            PostHogSDK.shared.debug(debug)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func reloadFeatureFlags(_ result: @escaping FlutterResult
    ) {
        PostHogSDK.shared.reloadFeatureFlags()
        result(nil)
    }

    private func awaitFeatureFlagsLoaded(_ result: @escaping FlutterResult
    ) {
        do {
            isLoadedSubject.sink { completion in
                if completion {
                    result(nil)
                }
            }
        } catch let error {
            result(FlutterError(code: "PosthogFlutterException", message: error.localizedDescription, details: nil))
        }
    }

    private func group(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let groupType = args["groupType"] as? String,
           let groupKey = args["groupKey"] as? String
        {
            let groupProperties = args["groupProperties"] as? [String: Any]
            PostHogSDK.shared.group(type: groupType, key: groupKey, groupProperties: groupProperties)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func register(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let value = args["value"]
        {
            PostHogSDK.shared.register([key: value])
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }

    private func unregister(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String
        {
            PostHogSDK.shared.unregister(key)
            result(nil)
        } else {
            _badArgumentError(result)
        }
    }
    
    private func flush(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.flush()
        result(nil)
    }

    // Return bad Arguments error
    private func _badArgumentError(_ result: @escaping FlutterResult) {
        result(FlutterError(
            code: "PosthogFlutterException", message: "Missing arguments!", details: nil
        ))
    }
}
