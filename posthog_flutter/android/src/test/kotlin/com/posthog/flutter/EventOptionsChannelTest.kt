package com.posthog.flutter

import com.posthog.PostHog
import com.posthog.PostHogEvent
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class EventOptionsChannelTest {
    private val options = mapOf("process_person_profile" to true, "custom_key" to "kept")

    @Test
    fun forwardsOptionsToEachNativeMethod() {
        val events = mutableListOf<PostHogEvent>()
        val config =
            PostHogAndroidConfig("event-options-test", "http://127.0.0.1:1").apply {
                preloadFeatureFlags = false
                captureApplicationLifecycleEvents = false
                captureDeepLinks = false
                captureScreenViews = false
                addBeforeSend { event ->
                    events.add(event)
                    // Keep AI events so captureAi returns their uuid.
                    if (event.event.startsWith("\$ai_")) event else null
                }
            }
        PostHogAndroid.setup(RuntimeEnvironment.getApplication(), config)
        try {
            val plugin = PosthogFlutterPlugin()
            val calls =
                listOf(
                    "capture" to mapOf("eventName" to "clicked"),
                    "screen" to mapOf("screenName" to "Home"),
                    "captureException" to mapOf("properties" to mapOf("\$exception_list" to emptyList<Any>())),
                    "alias" to mapOf("alias" to "alias-id"),
                    "identify" to mapOf("userId" to "user-id"),
                    "setPersonProperties" to mapOf("userPropertiesToSet" to mapOf("plan" to "pro")),
                    "group" to mapOf("groupType" to "company", "groupKey" to "acme"),
                )
            for ((method, arguments) in calls) {
                val result = Mockito.mock(MethodChannel.Result::class.java)
                plugin.onMethodCall(MethodCall(method, arguments + ("options" to options)), result)
                Mockito.verify(result).success(null)
            }

            assertEquals(
                listOf("clicked", "\$screen", "\$exception", "\$create_alias", "\$identify", "\$set", "\$groupidentify"),
                events.map { it.event },
            )
            for (event in events) {
                assertEquals<Map<String, Any?>?>(options, event.options, event.event)
            }
        } finally {
            PostHog.close()
        }
    }

    @Test
    fun captureAiReturnsTheQueuedEventUuid() {
        val events = mutableListOf<PostHogEvent>()
        val config =
            PostHogAndroidConfig("capture-ai-test", "http://127.0.0.1:1").apply {
                preloadFeatureFlags = false
                captureApplicationLifecycleEvents = false
                captureDeepLinks = false
                addBeforeSend { event ->
                    events.add(event)
                    event
                }
            }
        PostHogAndroid.setup(RuntimeEnvironment.getApplication(), config)
        try {
            val result = Mockito.mock(MethodChannel.Result::class.java)
            PosthogFlutterPlugin().onMethodCall(
                MethodCall(
                    "captureAi",
                    mapOf(
                        "eventName" to "\$ai_generation",
                        "properties" to mapOf("\$ai_model" to "gpt-4o"),
                        "options" to options,
                    ),
                ),
                result,
            )

            val captor = ArgumentCaptor.forClass(Any::class.java)
            Mockito.verify(result).success(captor.capture())
            val uuid = assertNotNull(captor.value as? String)
            UUID.fromString(uuid)
            val event = events.single()
            assertEquals("\$ai_generation", event.event)
            assertEquals("gpt-4o", event.properties?.get("\$ai_model"))
            assertEquals<Map<String, Any?>?>(options, event.options)
        } finally {
            PostHog.close()
        }
    }
}
