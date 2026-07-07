package com.posthog.flutter

import android.app.Activity
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

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

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_alias_returnsExpectedValue() {
        val plugin = PosthogFlutterPlugin()

        var arguments = mapOf("alias" to "abc")

        val call = MethodCall("alias", arguments)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(null)
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
    fun onMethodCall_captureNativeScreenshot_noActivity_returnsNull() {
        val plugin = PosthogFlutterPlugin()

        val call =
            MethodCall(
                "captureNativeScreenshot",
                mapOf("x" to 0, "y" to 0, "width" to 10, "height" to 10),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        // No activity attached, so capture degrades to null rather than crashing.
        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_captureNativeScreenshot_invalidDimensions_returnsError() {
        val plugin = PosthogFlutterPlugin()
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(Mockito.mock(Activity::class.java))
        plugin.onAttachedToActivity(binding)

        // Dimensions are validated before any activity view access, so a bare
        // mock Activity is enough to reach the zero-dimension guard.
        val call =
            MethodCall(
                "captureNativeScreenshot",
                mapOf("x" to 0, "y" to 0, "width" to 0, "height" to 0),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("INVALID_ARGUMENT"),
            Mockito.any(),
            Mockito.isNull(),
        )
    }

    @Test
    fun onMethodCall_captureNativeScreenshots_noActivity_returnsEmptyList() {
        val plugin = PosthogFlutterPlugin()

        val call =
            MethodCall(
                "captureNativeScreenshots",
                mapOf("views" to listOf(mapOf("x" to 0, "y" to 0, "width" to 10, "height" to 10))),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(emptyList<ByteArray?>())
    }

    @Test
    fun onMethodCall_captureNativeScreenshots_emptyViews_returnsEmptyList() {
        val plugin = PosthogFlutterPlugin()
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(Mockito.mock(Activity::class.java))
        plugin.onAttachedToActivity(binding)

        val call = MethodCall("captureNativeScreenshots", mapOf("views" to emptyList<Map<String, Int>>()))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(emptyList<ByteArray?>())
    }

    @Test
    fun onMethodCall_captureNativeScreenshots_zeroDimensionEntry_producesNullInResult() {
        val plugin = PosthogFlutterPlugin()
        val binding = Mockito.mock(ActivityPluginBinding::class.java)
        Mockito.`when`(binding.activity).thenReturn(Mockito.mock(Activity::class.java))
        plugin.onAttachedToActivity(binding)

        // Zero-dimension guard fires before any activity view access, so
        // captureNext inserts null and advances without crashing.
        val call =
            MethodCall(
                "captureNativeScreenshots",
                mapOf("views" to listOf(mapOf("x" to 0, "y" to 0, "width" to 0, "height" to 0))),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        @Suppress("UNCHECKED_CAST")
        val captor = org.mockito.ArgumentCaptor.forClass(List::class.java) as org.mockito.ArgumentCaptor<List<ByteArray?>>
        Mockito.verify(mockResult).success(captor.capture())
        assertEquals(1, captor.value.size)
        assertNull(captor.value[0])
    }

    @Test
    fun onMethodCall_enableNativeBridge_declinesWhenNotOccluded() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("enableNativeBridge", mapOf("episode" to 1))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_enableNativeBridge_declinesStaleEpisode() {
        val plugin = PosthogFlutterPlugin()
        plugin.isOccluded = true
        plugin.occlusionEpisode = 5

        val call = MethodCall("enableNativeBridge", mapOf("episode" to 4))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
    }

    @Test
    fun onMethodCall_enableNativeBridge_declineDoesNotDisarmBridge() {
        val plugin = PosthogFlutterPlugin()
        plugin.bridgeEnabled = true

        val call = MethodCall("enableNativeBridge", mapOf("episode" to 9))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(false)
        assertEquals(true, plugin.bridgeEnabled)
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
