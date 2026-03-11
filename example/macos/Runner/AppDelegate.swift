import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "posthog_flutter_example",
      binaryMessenger: controller.engine.binaryMessenger
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
