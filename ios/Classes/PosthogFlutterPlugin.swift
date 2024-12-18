import PostHog
#if os(iOS)
    import Flutter
    import UIKit
#elseif os(macOS)
    import AppKit
    import FlutterMacOS
#endif

public class PosthogFlutterPlugin: NSObject, FlutterPlugin {
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

    private let dispatchQueue = DispatchQueue(label: "com.posthog.PosthogFlutterPlugin",
                                              target: .global(qos: .utility))

    public static func initPlugin() {
        let autoInit = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.AUTO_INIT") as? Bool ?? true
        if !autoInit {
            print("[PostHog] com.posthog.posthog.AUTO_INIT is disabled!")
            return
        }

        let apiKey = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.API_KEY") as? String ?? ""

        let host = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.POSTHOG_HOST") as? String ?? PostHogConfig.defaultHost
        let captureApplicationLifecycleEvents = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS") as? Bool ?? false
        let debug = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.DEBUG") as? Bool ?? false

        setupPostHog([
            "apiKey": apiKey,
            "host": host,
            "captureApplicationLifecycleEvents": captureApplicationLifecycleEvents,
            "debug": debug,
        ])
    }

    private static func setupPostHog(_ posthogConfig: [String: Any]) {
        let apiKey = posthogConfig["apiKey"] as? String ?? ""
        if apiKey.isEmpty {
            print("[PostHog] apiKey is missing!")
            return
        }

        let host = posthogConfig["host"] as? String ?? PostHogConfig.defaultHost

        let config = PostHogConfig(
            apiKey: apiKey,
            host: host
        )
        config.captureScreenViews = false

        if let captureApplicationLifecycleEvents = posthogConfig["captureApplicationLifecycleEvents"] as? Bool {
            config.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents
        }
        if let debug = posthogConfig["debug"] as? Bool {
            config.debug = debug
        }
        if let flushAt = posthogConfig["flushAt"] as? Int {
            config.flushAt = flushAt
        }
        if let maxQueueSize = posthogConfig["maxQueueSize"] as? Int {
            config.maxQueueSize = maxQueueSize
        }
        if let maxBatchSize = posthogConfig["maxBatchSize"] as? Int {
            config.maxBatchSize = maxBatchSize
        }
        if let flushInterval = posthogConfig["flushInterval"] as? Int {
            config.flushIntervalSeconds = Double(flushInterval)
        }
        if let sendFeatureFlagEvents = posthogConfig["sendFeatureFlagEvents"] as? Bool {
            config.sendFeatureFlagEvent = sendFeatureFlagEvents
        }
        if let preloadFeatureFlags = posthogConfig["preloadFeatureFlags"] as? Bool {
            config.preloadFeatureFlags = preloadFeatureFlags
        }
        if let optOut = posthogConfig["optOut"] as? Bool {
            config.optOut = optOut
        }
        if let personProfiles = posthogConfig["personProfiles"] as? String {
            switch personProfiles {
            case "never":
                config.personProfiles = .never
            case "always":
                config.personProfiles = .always
            case "identifiedOnly":
                config.personProfiles = .identifiedOnly
            default:
                break
            }
        }
        if let dataMode = posthogConfig["dataMode"] as? String {
            switch dataMode {
            case "wifi":
                config.dataMode = .wifi
            case "cellular":
                config.dataMode = .cellular
            case "any":
                config.dataMode = .any
            default:
                break
            }
        }
        #if os(iOS)
            if let sessionReplay = posthogConfig["sessionReplay"] as? Bool {
                config.sessionReplay = sessionReplay
            }
            // disabled since Dart has native libs such as http/dio and dont use the ios URLSession
            config.sessionReplayConfig.captureNetworkTelemetry = false
        #endif

        // Update SDK name and version
        postHogSdkName = "posthog-flutter"
        postHogVersion = postHogFlutterVersion

        PostHogSDK.shared.setup(config)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            setup(call, result: result)
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
        case "close":
            close(result)
        case "sendMetaEvent":
            sendMetaEvent(call, result: result)
        case "sendFullSnapshot":
            sendFullSnapshot(call, result: result)
        case "isSessionReplayActive":
            isSessionReplayActive(result: result)
        case "getSessionId":
            getSessionId(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func sendMetaEvent(_ call: FlutterMethodCall,
                               result: @escaping FlutterResult)
    {
        #if os(iOS)
            let date = Date()
            let timestamp = dateToMillis(date)
            if let args = call.arguments as? [String: Any] {
                let width = args["width"] as? Int ?? 0
                let height = args["height"] as? Int ?? 0
                let screen = args["screen"] as? String ?? ""

                if width == 0 || height == 0 {
                    _badArgumentError(result)
                    return
                }

                dispatchQueue.async {
                    var snapshotsData: [Any] = []
                    let data: [String: Any] = ["width": width, "height": height, "href": screen]

                    let snapshotData: [String: Any] = ["type": 4, "data": data, "timestamp": timestamp]
                    snapshotsData.append(snapshotData)

                    PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData], timestamp: date)
                }

                result(nil)
            } else {
                _badArgumentError(result)
            }
        #else
            result(nil)
        #endif
    }

    private func sendFullSnapshot(_ call: FlutterMethodCall,
                                  result: @escaping FlutterResult)
    {
        #if os(iOS)
            let date = Date()
            let timestamp = dateToMillis(date)
            if let args = call.arguments as? [String: Any] {
                let id = args["id"] as? Int ?? 1
                let x = args["x"] as? Int ?? 0
                let y = args["y"] as? Int ?? 0

                guard let imageBytes = args["imageBytes"] as? FlutterStandardTypedData else {
                    _badArgumentError(result)
                    return
                }

                dispatchQueue.async {
                    guard let image = UIImage(data: imageBytes.data) else {
                        // bad data but we cannot do this in the calling thread
                        // otherwise we are doing slow operatios in the main thread
                        return
                    }

                    guard let base64 = imageToBase64(image) else {
                        // bad data but we cannot do this in the calling thread
                        // otherwise we are doing slow operatios in the main thread
                        return
                    }

                    var snapshotsData: [Any] = []
                    var wireframes: [Any] = []

                    let wireframe: [String: Any] = [
                        "id": id,
                        "x": x,
                        "y": y,
                        "width": Int(image.size.width),
                        "height": Int(image.size.height),
                        "type": "screenshot",
                        "base64": base64,
                        "style": [:],
                    ]

                    wireframes.append(wireframe)
                    let initialOffset = ["top": 0, "left": 0]
                    let data: [String: Any] = ["initialOffset": initialOffset, "wireframes": wireframes]
                    let snapshotData: [String: Any] = ["type": 2, "data": data, "timestamp": timestamp]
                    snapshotsData.append(snapshotData)

                    PostHogSDK.shared.capture("$snapshot", properties: ["$snapshot_source": "mobile", "$snapshot_data": snapshotsData], timestamp: date)
                }

                result(nil)
            } else {
                _badArgumentError(result)
            }
        #else
            result(nil)
        #endif
    }

    private func isSessionReplayActive(result: @escaping FlutterResult) {
        #if os(iOS)
            result(PostHogSDK.shared.isSessionReplayActive())
        #else
            result(false)
        #endif
    }

    private func setup(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        if let args = call.arguments as? [String: Any] {
            PosthogFlutterPlugin.setupPostHog(args)
            result(nil)
        } else {
            _badArgumentError(result)
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

    private func close(_ result: @escaping FlutterResult) {
        PostHogSDK.shared.close()
        result(nil)
    }

    private func getSessionId(result: @escaping FlutterResult) {
        result(PostHogSDK.shared.getSessionId())
    }

    // Return bad Arguments error
    private func _badArgumentError(_ result: @escaping FlutterResult) {
        result(FlutterError(
            code: "PosthogFlutterException", message: "Missing arguments!", details: nil
        ))
    }
}
