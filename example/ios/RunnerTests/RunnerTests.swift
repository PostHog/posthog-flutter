import Flutter
import UIKit
import XCTest

@testable import posthog_flutter

// Unit tests of the Swift portion of this plugin's implementation.
//
// Mirrors the Android `PosthogFlutterPluginTest`. Run from the example app's
// iOS test target.
//
// See https://developer.apple.com/documentation/xctest for more information
// about using XCTest.

class RunnerTests: XCTestCase {
    func testCaptureLogRoutesToCaptureLogAndSucceeds() {
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

        // Routed through the public PostHogSDK.shared.captureLog (with W3C trace
        // fields); the SDK is not set up in the test, so it no-ops and we still
        // succeed with a nil result.
        XCTAssertTrue(resultCalled)
        XCTAssertNil(resultValue)
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

    func testSendFullSnapshotReportsUndecodableImageAsError() {
        let reply = sendFullSnapshot(Data([0x00, 0x01, 0x02]))

        let error = reply as? FlutterError
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, "PosthogFlutterException")
    }

    func testSendFullSnapshotSucceedsForDecodableImage() {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        XCTAssertNil(sendFullSnapshot(png))
    }

    private func sendFullSnapshot(_ imageBytes: Data) -> Any? {
        let call = FlutterMethodCall(
            methodName: "sendFullSnapshot",
            arguments: ["imageBytes": FlutterStandardTypedData(bytes: imageBytes), "id": 1, "x": 0, "y": 0]
        )
        let replied = expectation(description: "reply")
        var reply: Any?
        PosthogFlutterPlugin().handle(call) { value in
            reply = value
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
        return reply
    }
}
