import Flutter
import PostHog
@testable import posthog_flutter
import UIKit
import XCTest

// Unit tests of the Swift portion of this plugin's implementation.
//
// Mirrors the Android `PosthogFlutterPluginTest`. Run from the example app's
// iOS test target.
//
// See https://developer.apple.com/documentation/xctest for more information
// about using XCTest.

class RunnerTests: XCTestCase {
    func testCaptureLogRoutesToCaptureLogAndSucceeds() {
        var records: [PostHogLogRecord] = []
        let config = PostHogConfig(projectToken: "log-channel-test", host: "http://127.0.0.1:1")
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        config.setBeforeSend { _ in nil }
        config.logs.setBeforeSend { record in
            records.append(record)
            return nil
        }
        PostHogSDK.shared.close()
        PostHogSDK.shared.setup(config)
        defer { PostHogSDK.shared.close() }
        let plugin = PosthogFlutterPlugin()

        let arguments: [String: Any] = [
            "body": "checkout completed",
            "level": "warn",
            "attributes": ["order_id": "ord_789"],
            "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
            "spanId": "00f067aa0ba902b7",
            "traceFlags": 1,
        ]
        let call = FlutterMethodCall(methodName: "captureLog", arguments: arguments)

        var resultCalled = false
        var resultValue: Any?
        plugin.handle(call) { value in
            resultCalled = true
            resultValue = value
        }

        XCTAssertTrue(resultCalled)
        XCTAssertNil(resultValue)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.body, "checkout completed")
        XCTAssertEqual(records.first?.level, .warn)
        XCTAssertEqual(records.first?.attributes["order_id"] as? String, "ord_789")
        XCTAssertEqual(records.first?.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertEqual(records.first?.spanId, "00f067aa0ba902b7")
        XCTAssertEqual(records.first?.traceFlags, 1)

        plugin.handle(FlutterMethodCall(methodName: "captureLog", arguments: ["body": "default", "traceFlags": 0])) { _ in }
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.body, "default")
        XCTAssertEqual(records.last?.level, .info)
        XCTAssertEqual(records.last?.traceFlags, 0)
        XCTAssertNil(records.last?.traceId)
        XCTAssertNil(records.last?.spanId)
    }

    func testCaptureLogMissingBodyReturnsError() {
        let plugin = PosthogFlutterPlugin()

        let call = FlutterMethodCall(methodName: "captureLog", arguments: [String: Any]())

        var resultValue: Any?
        plugin.handle(call) { value in
            resultValue = value
        }

        let error = resultValue as? FlutterError
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, "PosthogFlutterException")
    }
}
