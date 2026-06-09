package com.posthog.flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class PosthogFlutterPluginTest {
    @Test
    fun onMethodCall_identify_returnsExpectedValue() {
        val plugin = PosthogFlutterPlugin()

        var arguments = mapOf("userId" to "abc")

        val call = MethodCall("identify", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_alias_returnsExpectedValue() {
        val plugin = PosthogFlutterPlugin()

        var arguments = mapOf("alias" to "abc")

        val call = MethodCall("alias", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_captureLog_routesToCaptureLogAndSucceeds() {
        val plugin = PosthogFlutterPlugin()

        val arguments =
            mapOf(
                "body" to "checkout completed",
                "level" to "warn",
                "attributes" to mapOf("order_id" to "ord_789"),
                "traceId" to "4bf92f3577b34da6a3ce929d0e0e4736",
                "spanId" to "00f067aa0ba902b7",
                "traceFlags" to 1,
            )

        val call = MethodCall("captureLog", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        // Routed through the public PostHog.captureLog (with W3C trace fields);
        // the SDK is not set up in the test, so it no-ops and we still succeed.
        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_captureLog_missingBody_returnsError() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("captureLog", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("PosthogFlutterException"),
            Mockito.any(),
            Mockito.isNull(),
        )
    }

    @Test
    fun onMethodCall_getFeatureFlagResult_missingKey_returnsError() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("getFeatureFlagResult", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("PosthogFlutterException"),
            Mockito.eq("Missing argument: key"),
            Mockito.isNull(),
        )
    }
}
