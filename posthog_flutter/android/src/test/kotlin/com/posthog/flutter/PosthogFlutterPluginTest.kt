package com.posthog.flutter

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

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
    fun onMethodCall_sendMetaEvent_repliesAfterWorkDropsOnDetachRecoversOnReattach() {
        val plugin = PosthogFlutterPlugin()
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(binding.applicationContext).thenReturn(Mockito.mock(Context::class.java))
        Mockito.`when`(binding.binaryMessenger).thenReturn(Mockito.mock(BinaryMessenger::class.java))
        plugin.onAttachedToEngine(binding)

        val call = MethodCall("sendMetaEvent", mapOf("width" to 10, "height" to 20, "screen" to "Home"))

        // Asserts only that no reply happens synchronously in the handler.
        // Actual delivery after the worker runs is not observable here (the
        // stubbed test looper drops posts) and is covered end to end.
        val whileAttached: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, whileAttached)
        Mockito.verify(whileAttached, Mockito.never()).success(null)

        plugin.onDetachedFromEngine(binding)

        // Shut-down executor: the submission is dropped and answered
        // immediately, never thrown.
        val afterDetach: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, afterDetach)
        Mockito.verify(afterDetach).success(null)

        // Reattach recreates the executor: submissions are accepted again
        // instead of hitting the immediate drop path.
        plugin.onAttachedToEngine(binding)
        val afterReattach: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, afterReattach)
        Mockito.verify(afterReattach, Mockito.never()).success(null)
    }

    @Test
    fun onMethodCall_setCaptureNativeScreens_returnsSuccess() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("setCaptureNativeScreens", mapOf("enabled" to false))
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

    @Test
    fun bootstrapConfigFromMap_fullMap_decodesAllFields() {
        val config =
            bootstrapConfigFromMap(
                mapOf(
                    "distinctId" to "user-123",
                    "isIdentifiedId" to true,
                    "featureFlags" to mapOf("beta-ui" to "variant-a", "legacy" to true),
                    "featureFlagPayloads" to mapOf("beta-ui" to mapOf("color" to "blue")),
                ),
            )

        assertEquals("user-123", config.distinctId)
        assertTrue(config.isIdentifiedId)
        assertEquals(mapOf("beta-ui" to "variant-a", "legacy" to true), config.featureFlags)
        assertEquals(mapOf("beta-ui" to mapOf("color" to "blue")), config.featureFlagPayloads)
    }

    @Test
    fun bootstrapConfigFromMap_emptyMap_usesDefaults() {
        val config = bootstrapConfigFromMap(emptyMap())

        assertNull(config.distinctId)
        assertFalse(config.isIdentifiedId)
        assertNull(config.featureFlags)
        assertNull(config.featureFlagPayloads)
    }

    @Test
    fun bootstrapConfigFromMap_wrongTypes_fallBackToDefaults() {
        val config =
            bootstrapConfigFromMap(
                mapOf(
                    "distinctId" to 42,
                    "isIdentifiedId" to "yes",
                    "featureFlags" to listOf("beta-ui"),
                ),
            )

        assertNull(config.distinctId)
        assertFalse(config.isIdentifiedId)
        assertNull(config.featureFlags)
        assertNull(config.featureFlagPayloads)
    }
}
