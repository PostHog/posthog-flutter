package com.posthog.flutter

import android.app.Activity
import android.content.Context
import com.google.firebase.FirebaseApp
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.mockito.ArgumentCaptor
import org.mockito.Mockito
import java.nio.ByteBuffer
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
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
    @BeforeTest
    fun resetSharedRoute() {
        PosthogFlutterPlugin.resetPushIdentityRouteForTesting()
    }

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
        val binding = attach(plugin, Mockito.mock(BinaryMessenger::class.java))

        val call = MethodCall("sendMetaEvent", mapOf("width" to 10, "height" to 20, "screen" to "Home"))

        // Asserts only that no reply happens synchronously in the handler.
        // Actual delivery after the worker runs is not observable here (the
        // stubbed test looper drops posts) and is covered end to end.
        val whileAttached: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, whileAttached)
        Mockito.verify(whileAttached, Mockito.never()).success(null)

        plugin.onDetachedFromEngine(binding)

        val afterDetach: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, afterDetach)
        Mockito.verify(afterDetach).success(null)

        // No immediate drop reply proves the executor was recreated.
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

    @Test
    fun onMethodCall_registerPushNotificationToken_withAppId_returnsSuccess() {
        val plugin = PosthogFlutterPlugin()

        val call =
            MethodCall(
                "registerPushNotificationToken",
                mapOf("deviceToken" to "token-abc", "appId" to "my-firebase-project"),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_registerPushNotificationToken_missingDeviceToken_returnsError() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("registerPushNotificationToken", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("PosthogFlutterException"),
            Mockito.eq("Missing argument: deviceToken"),
            Mockito.isNull(),
        )
    }

    @Test
    fun onMethodCall_registerPushNotificationToken_noAppIdAndNoFirebase_reportsSkip() {
        val plugin = PosthogFlutterPlugin()

        // The FirebaseApp stub isn't initialized, so the reflective project-id
        // fallback finds nothing; the missing id is reported as an error so Dart
        // logs the skip instead of seeing a false success.
        FirebaseApp.projectId = null
        val call = MethodCall("registerPushNotificationToken", mapOf("deviceToken" to "token-abc"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("PosthogFlutterException"),
            Mockito.contains("no appId provided"),
            Mockito.isNull(),
        )
        Mockito.verify(mockResult, Mockito.never()).success(Mockito.any())
    }

    @Test
    fun onMethodCall_registerPushNotificationToken_noAppIdWithFirebase_resolvesProjectId() {
        val plugin = PosthogFlutterPlugin()

        // With the stub initialized, the reflective fallback resolves a project
        // id and registration proceeds instead of erroring.
        FirebaseApp.projectId = "stub-project"
        try {
            val call = MethodCall("registerPushNotificationToken", mapOf("deviceToken" to "token-abc"))
            val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(call, mockResult)

            Mockito.verify(mockResult).success(null)
            Mockito.verify(mockResult, Mockito.never()).error(Mockito.any(), Mockito.any(), Mockito.any())
        } finally {
            FirebaseApp.projectId = null
        }
    }

    @Test
    fun onMethodCall_registerPushNotificationToken_blankDeviceToken_returnsError() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("registerPushNotificationToken", mapOf("deviceToken" to "  "))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            Mockito.eq("PosthogFlutterException"),
            Mockito.eq("Missing argument: deviceToken"),
            Mockito.isNull(),
        )
        Mockito.verify(mockResult, Mockito.never()).success(Mockito.any())
    }

    @Test
    fun onMethodCall_unregisterPushNotificationToken_returnsSuccess() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("unregisterPushNotificationToken", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_capturePushNotificationOpened_dropsIosOnlySubtitle() {
        val plugin = PosthogFlutterPlugin()

        // subtitle has no Android counterpart; it must be ignored rather than
        // rejected, so iOS-shaped calls from shared Dart code still succeed.
        val call =
            MethodCall(
                "capturePushNotificationOpened",
                mapOf(
                    "title" to "Title",
                    "subtitle" to "Subtitle",
                    "body" to "Body",
                    "payload" to mapOf("posthog" to """{"campaign_id":"x"}"""),
                    "action" to "reply",
                ),
            )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_capturePushNotificationOpened_noArguments_returnsSuccess() {
        val plugin = PosthogFlutterPlugin()

        val call = MethodCall("capturePushNotificationOpened", mapOf<String, Any>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(null)
    }

    // The stubbed test Looper makes runOnMainThread run inline (myLooper and
    // getMainLooper both default to null), so mint round trips are synchronous here.

    private fun attach(
        plugin: PosthogFlutterPlugin,
        messenger: BinaryMessenger,
    ): FlutterPlugin.FlutterPluginBinding {
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        Mockito.`when`(binding.applicationContext).thenReturn(Mockito.mock(Context::class.java))
        Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)
        plugin.onAttachedToEngine(binding)
        return binding
    }

    private fun setupWithIdentityProvider(plugin: PosthogFlutterPlugin): (String, String, (String?) -> Unit) -> Unit {
        val call =
            MethodCall(
                "setup",
                mapOf("projectToken" to "test-token", "pushIdentityProviderEnabled" to true),
            )
        plugin.onMethodCall(call, Mockito.mock(MethodChannel.Result::class.java))
        return assertNotNull(plugin.lastBuiltConfig?.pushIdentityProvider)
    }

    private fun replyToMint(
        messenger: BinaryMessenger,
        response: ByteBuffer?,
        invocation: Int = 1,
    ): MethodCall {
        val messageCaptor = ArgumentCaptor.forClass(ByteBuffer::class.java)
        val replyCaptor = ArgumentCaptor.forClass(BinaryMessenger.BinaryReply::class.java)
        Mockito
            .verify(messenger, Mockito.times(invocation))
            .send(Mockito.eq("posthog_flutter"), messageCaptor.capture(), replyCaptor.capture())
        val message = messageCaptor.value.also { it.rewind() }
        replyCaptor.value.reply(response)
        return StandardMethodCodec.INSTANCE.decodeMethodCall(message)
    }

    private fun successEnvelope(value: Any?): ByteBuffer = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value).also { it.rewind() }

    private data class ProviderHarness(
        val plugin: PosthogFlutterPlugin,
        val messenger: BinaryMessenger,
        val binding: FlutterPlugin.FlutterPluginBinding,
        val provider: (String, String, (String?) -> Unit) -> Unit,
    )

    private fun pluginWithProvider(): ProviderHarness {
        val plugin = PosthogFlutterPlugin()
        val messenger = Mockito.mock(BinaryMessenger::class.java)
        val binding = attach(plugin, messenger)
        return ProviderHarness(plugin, messenger, binding, setupWithIdentityProvider(plugin))
    }

    @Test
    fun pushIdentityProvider_mintsThroughEngineThatRanSetup() {
        val owner = pluginWithProvider()

        var minted: String? = null
        owner.provider("user-1", "com.example.app") { minted = it }

        val sent = replyToMint(owner.messenger, successEnvelope("minted-token"))
        assertEquals("pushIdentityProvider", sent.method)
        assertEquals(
            mapOf("distinctId" to "user-1", "appId" to "com.example.app"),
            sent.arguments,
        )
        assertEquals("minted-token", minted)
    }

    @Test
    fun pushIdentityProvider_dartError_declinesWithNullToken() {
        val owner = pluginWithProvider()

        var minted: String? = "sentinel"
        owner.provider("user-1", "com.example.app") { minted = it }
        replyToMint(
            owner.messenger,
            StandardMethodCodec.INSTANCE
                .encodeErrorEnvelope("MINT_FAILED", "backend down", null)
                .also { it.rewind() },
        )

        assertNull(minted)
    }

    @Test
    fun pushIdentityProvider_notImplemented_declinesWithNullToken() {
        val owner = pluginWithProvider()

        var minted: String? = "sentinel"
        owner.provider("user-1", "com.example.app") { minted = it }
        // A null binary reply is how the channel signals notImplemented.
        replyToMint(owner.messenger, null)

        assertNull(minted)
    }

    @Test
    fun pushIdentityProvider_secondarySetupNeitherStealsNorOrphansRoute() {
        val owner = pluginWithProvider()

        // A background isolate (firebase_messaging pattern) legitimately re-runs
        // setup() with the same provider-enabled config. The native SDK no-ops
        // the duplicate setup; the mint route must stay with the live owner...
        val background = PosthogFlutterPlugin()
        val backgroundMessenger = Mockito.mock(BinaryMessenger::class.java)
        val backgroundBinding = attach(background, backgroundMessenger)
        setupWithIdentityProvider(background)

        var minted: String? = null
        owner.provider("user-1", "app") { minted = it }
        replyToMint(owner.messenger, successEnvelope("tok-1"))
        assertEquals("tok-1", minted)
        Mockito
            .verify(backgroundMessenger, Mockito.never())
            .send(Mockito.any(), Mockito.any(), Mockito.any())

        // ...and its detach must not orphan the owner's route.
        background.onDetachedFromEngine(backgroundBinding)
        owner.provider("user-1", "app") { minted = it }
        replyToMint(owner.messenger, successEnvelope("tok-2"), invocation = 2)
        assertEquals("tok-2", minted)
    }

    @Test
    fun pushIdentityProvider_secondaryEngineNeitherStealsNorClearsRoute() {
        val owner = pluginWithProvider()

        // A secondary engine (firebase_messaging-style background isolate)
        // attaches without running setup: it must not steal the mint route...
        val background = PosthogFlutterPlugin()
        val backgroundMessenger = Mockito.mock(BinaryMessenger::class.java)
        val backgroundBinding = attach(background, backgroundMessenger)

        var minted: String? = null
        owner.provider("user-1", "app") { minted = it }
        replyToMint(owner.messenger, successEnvelope("tok-1"))
        assertEquals("tok-1", minted)
        Mockito
            .verify(backgroundMessenger, Mockito.never())
            .send(Mockito.any(), Mockito.any(), Mockito.any())

        // ...nor null it when it detaches.
        background.onDetachedFromEngine(backgroundBinding)
        owner.provider("user-1", "app") { minted = it }
        replyToMint(owner.messenger, successEnvelope("tok-2"), invocation = 2)
        assertEquals("tok-2", minted)
    }

    @Test
    fun pushIdentityProvider_declinesPromptlyAfterOwnerDetach() {
        val owner = pluginWithProvider()

        // Declines synchronously instead of stalling the native 10s mint
        // watchdog on a dead messenger.
        owner.plugin.onDetachedFromEngine(owner.binding)
        var declined = false
        owner.provider("user-1", "app") { declined = it == null }

        assertTrue(declined)
        Mockito
            .verify(owner.messenger, Mockito.never())
            .send(Mockito.any(), Mockito.any(), Mockito.any())
    }

    @Test
    fun pushIdentityProvider_reSetupAfterDetachRepointsRoute() {
        val owner = pluginWithProvider()
        owner.plugin.onDetachedFromEngine(owner.binding)

        val reattachedMessenger = Mockito.mock(BinaryMessenger::class.java)
        attach(owner.plugin, reattachedMessenger)
        setupWithIdentityProvider(owner.plugin)

        var minted: String? = null
        owner.provider("user-1", "app") { minted = it }
        replyToMint(reattachedMessenger, successEnvelope("tok-3"))
        assertEquals("tok-3", minted)
    }

    @Test
    fun pushIdentityProvider_ownerDetachPromotesSurvivingSetupEngine() {
        // The orphaning ordering: a background isolate sets up first and owns the
        // route, the main engine sets up during the overlap (anchor skipped), then
        // the background engine dies. The route must promote to the surviving main
        // engine instead of declining for the rest of the process.
        val background = pluginWithProvider()

        val main = PosthogFlutterPlugin()
        val mainMessenger = Mockito.mock(BinaryMessenger::class.java)
        attach(main, mainMessenger)
        setupWithIdentityProvider(main)

        background.plugin.onDetachedFromEngine(background.binding)

        var minted: String? = null
        background.provider("user-1", "app") { minted = it }
        replyToMint(mainMessenger, successEnvelope("tok-main"))
        assertEquals("tok-main", minted)
        Mockito
            .verify(background.messenger, Mockito.never())
            .send(Mockito.any(), Mockito.any(), Mockito.any())
    }

    @Test
    fun pushIdentityProvider_detachedCandidateIsNeverPromoted() {
        // A candidate that detached before the owner must not be resurrected:
        // owner detach with no survivors declines instead of routing to a dead channel.
        val owner = pluginWithProvider()

        val background = PosthogFlutterPlugin()
        val backgroundMessenger = Mockito.mock(BinaryMessenger::class.java)
        val backgroundBinding = attach(background, backgroundMessenger)
        setupWithIdentityProvider(background)

        background.onDetachedFromEngine(backgroundBinding)
        owner.plugin.onDetachedFromEngine(owner.binding)

        var declined = false
        owner.provider("user-1", "app") { declined = it == null }

        assertTrue(declined)
        Mockito
            .verify(backgroundMessenger, Mockito.never())
            .send(Mockito.any(), Mockito.any(), Mockito.any())
    }
}
