import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "posthog_flutter_example",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { (call, result) in
      if call.method == "triggerNativeCrash" {
        // Trigger a native crash by index out of range
        let array: [Int] = []
        _ = array[99]
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
