import Flutter
import UIKit
import PostHog

public class PosthogFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "posthog_flutter", binaryMessenger: registrar.messenger())
    let instance = PosthogFlutterPlugin()
    initPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
    
   public static func initPlugin(){
    // Initialise PostHog
       let postHogApiKey = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.API_KEY") as? String ?? ""
       let postHogHost = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.POSTHOG_HOST") as? String ?? "https://app.posthog.com"
         let postHogCaptureLifecyleEvents = Bundle.main.object(forInfoDictionaryKey: "com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS") as? Bool ?? false
         
         let config = PostHogConfig(
           apiKey: postHogApiKey,
           host: postHogHost
         )
         config.captureApplicationLifecycleEvents = postHogCaptureLifecyleEvents
         PostHogSDK.shared.setup(config)
       //
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
        getPlatformVersion(call, result: result)
    case "getFeatureFlag":
        getFeatureFlag(call, result: result)
    case "isFeatureEnabled":
        isFeatureEnabled(call, result: result)
    case "getFeatureFlagPayload":
        getFeatureFlagPayload(call, result: result)
    case "getFeatureFlagAndPayload":
        getFeatureFlagAndPayload(call, result: result)
    case "identify":
        identify(call, result: result)
    case "capture":
        capture(call, result: result)
    case "screen":
        screen(call, result: result)
    case "alias":
        alias(call, result: result)
    case "distinctId":
        distinctId(call, result: result)
    case "reset":
        reset(call, result: result)
    case "enable":
        enable(call, result: result)
    case "disable":
        disable(call, result: result)
    case "reloadFeatureFlags":
        reloadFeatureFlags(call, result: result)
    case "group":
        group(call, result: result)
    case "register":
        register(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

    private func getPlatformVersion(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        result("iOS " + UIDevice.current.systemVersion)
    }
    
    private func getFeatureFlag(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
            
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String {
           let value = PostHogSDK.shared.getFeatureFlag(featureFlagKey)
            result(value)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func isFeatureEnabled(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String {
            let value : Bool = PostHogSDK.shared.isFeatureEnabled(featureFlagKey)
            result(value)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func getFeatureFlagPayload(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String {
            let value : Any? = PostHogSDK.shared.getFeatureFlagPayload(featureFlagKey)
            result(value)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func getFeatureFlagAndPayload(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let featureFlagKey = args["key"] as? String {
            let status : Any? = PostHogSDK.shared.getFeatureFlag(featureFlagKey)
            let payload : Any? = PostHogSDK.shared.getFeatureFlagPayload(featureFlagKey)
            var featureAndPayload : Dictionary<String, Any?> = [String: Any?]()
            
            if (status == nil){
                featureAndPayload["isEnabled"] = false
            }
            if (status is String){
                featureAndPayload["isEnabled"] = true
                featureAndPayload["variant"] = status
            }else {
                featureAndPayload["isEnabled"] = status
            }
            featureAndPayload["data"] = payload
            
            result(featureAndPayload)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func identify(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let userId = args["userId"] as? String,
           let propertiesData = args["properties"] as? Dictionary<String,Any> {
            PostHogSDK.shared.identify(
                userId,
                userProperties: propertiesData
            )
            result(true)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func capture(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let eventName = args["eventName"] as? String,
           let propertiesData = args["properties"] as? Dictionary<String,Any> {
            PostHogSDK.shared.capture(
                eventName,
                userProperties: propertiesData
            )
            result(true)
          } else {
              _badArgumentError(result: result)
          }
        
    }
    
    private func screen(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let screenName = args["screenName"] as? String,
           let propertiesData = args["properties"] as? Dictionary<String,Any> {
            PostHogSDK.shared.screen(
                screenName,
                properties: propertiesData
            )
            result(true)
          } else {
              _badArgumentError(result: result)
          }
        
    }
    
    private func alias(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let alias = args["alias"] as? String {
            PostHogSDK.shared.alias(alias)
            result(true)
          } else {
              _badArgumentError(result: result)
          }
        
    }
    
    private func distinctId(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        let val = PostHogSDK.shared.getDistinctId()
        result(val)
    }
    
    private func reset(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        PostHogSDK.shared.reset()
        result(true)
    }
    
    private func enable(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        PostHogSDK.shared.optIn()
        result(true)
        
    }
    
    private func disable(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        PostHogSDK.shared.optOut()
        result(true)
    }
    
    private func reloadFeatureFlags(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        PostHogSDK.shared.reloadFeatureFlags()
        result(true)
    }
    
    private func group(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let groupType = args["groupType"] as? String,
           let groupKey = args["groupKey"] as? String,
           let groupProperties = args["groupProperties"] as? Dictionary<String,Any>{
            PostHogSDK.shared.group(type: groupType, key: groupKey, groupProperties: groupProperties)
            result(true)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    private func register(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ){
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let value = args["value"] {
            PostHogSDK.shared.register([key: value])
            result(true)
          } else {
              _badArgumentError(result: result)
          }
    }
    
    // Return bad Arguments error
    private func _badArgumentError(result: @escaping FlutterResult) {
        result(FlutterError.init(
            code: "bad args", message: nil, details: nil
        ))
    }
    
    
}
