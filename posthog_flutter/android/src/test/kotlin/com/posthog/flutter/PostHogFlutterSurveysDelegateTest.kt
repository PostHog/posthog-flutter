package com.posthog.flutter

import android.os.Looper
import com.posthog.PostHogBeforeSend
import com.posthog.PostHogInterface
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import com.posthog.android.surveys.PostHogSurveysIntegration
import com.posthog.internal.PostHogPreferences
import com.posthog.internal.PostHogSerializer
import com.posthog.surveys.Survey
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class PostHogFlutterSurveysDelegateTest {
    private val context = RuntimeEnvironment.getApplication()
    private val apiKey = "survey-resume-${UUID.randomUUID()}"
    private val events = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val messages = mutableListOf<Pair<String, Any?>>()

    private lateinit var preferences: PostHogPreferences

    private fun start(partial: Boolean): Pair<PostHogInterface, PostHogFlutterSurveysDelegate> {
        val channel = Mockito.mock(MethodChannel::class.java)
        Mockito
            .doAnswer { call ->
                messages.add(call.getArgument<String>(0) to call.getArgument<Any?>(1))
                null
            }.`when`(channel)
            .invokeMethod(Mockito.anyString(), Mockito.any())
        val delegate = PostHogFlutterSurveysDelegate(channel)
        val config =
            PostHogAndroidConfig(apiKey, "http://127.0.0.1:1").apply {
                preloadFeatureFlags = false
                surveys = true
                surveysConfig.surveysDelegate = delegate
                addBeforeSend(
                    PostHogBeforeSend { event ->
                        if (event.event.startsWith("survey ")) events.add(event.event to event.properties.orEmpty().toMap())
                        null
                    },
                )
            }
        val sdk = PostHogAndroid.with(context, config)
        preferences = assertNotNull(config.cachePreferences)
        val integration = config.integrations.filterIsInstance<PostHogSurveysIntegration>().single()
        val survey =
            assertNotNull(
                PostHogSerializer(config)
                    .deserializeList<Survey>(
                        listOf(
                            mapOf(
                                "id" to "resume-survey",
                                "name" to "Feedback",
                                "type" to "popover",
                                "start_date" to "2026-01-01T00:00:00Z",
                                "enable_partial_responses" to partial,
                                "questions" to
                                    listOf(
                                        mapOf("id" to "first", "type" to "open", "question" to "First?", "optional" to true),
                                        mapOf("id" to "second", "type" to "open", "question" to "Second?"),
                                    ),
                            ),
                        ),
                    )?.single(),
            )
        integration.onSurveysLoaded(listOf(survey))
        shadowOf(Looper.getMainLooper()).idle()
        return sdk to delegate
    }

    private fun shown(): Map<*, *> = messages.last { it.first == "showSurvey" }.second as Map<*, *>

    private fun PostHogFlutterSurveysDelegate.action(
        type: String,
        presentation: Map<*, *>,
        index: Int = 0,
        response: String? = null,
    ): MethodChannel.Result {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        handleSurveyAction(
            type,
            mapOf(
                "presentationId" to assertNotNull(presentation["presentationId"]),
                "index" to index,
            ) + (response?.let { mapOf("response" to it) } ?: emptyMap()),
            result,
        )
        return result
    }

    @Test
    fun resumesPersistedAnswersAndSubmissionIdThroughFlutterBridge() {
        for (partial in listOf(true, false)) {
            events.clear()
            messages.clear()
            val (firstSdk, firstDelegate) = start(partial)
            val first = shown()
            try {
                assertEquals(0, first["initialQuestionIndex"])
                firstDelegate.action("shown", first)
                val reply = firstDelegate.action("response", first, response = "Saved answer")
                Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to false))
                assertEquals(if (partial) 1 else 0, events.count { it.first == "survey sent" })
            } finally {
                firstSdk.close()
            }
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals("hideSurveys", messages.last().first)
            val partialEvent = events.lastOrNull { it.first == "survey sent" }?.second
            if (partial) assertEquals(false, partialEvent?.get("\$survey_completed"))

            val (resumedSdk, resumedDelegate) = start(partial)
            try {
                val resumed = shown()
                assertEquals(1, resumed["initialQuestionIndex"])
                assertNotEquals(first["presentationId"], resumed["presentationId"])
                val stale = resumedDelegate.action("response", first, response = "Stale")
                Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
                resumedDelegate.action("shown", resumed)
                val reply = resumedDelegate.action("response", resumed, 1, "Final answer")
                Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to true))
                val sent = events.filter { it.first == "survey sent" }
                assertEquals(if (partial) 2 else 1, sent.size)
                val completed = sent.last().second
                assertEquals("Saved answer", completed["\$survey_response_first"])
                assertEquals("Final answer", completed["\$survey_response_second"])
                assertEquals(true, completed["\$survey_completed"])
                assertNotNull(completed["\$survey_submission_id"])
                if (partial) assertEquals(partialEvent?.get("\$survey_submission_id"), completed["\$survey_submission_id"])
                assertTrue((preferences.getValue(PostHogPreferences.SURVEY_PROGRESS) as? Map<*, *>).isNullOrEmpty())
            } finally {
                resumedSdk.close()
                preferences.clear()
            }
        }
    }

    @Test
    fun dismissalAndResetClearSavedProgressAndRejectOldActions() {
        for (reset in listOf(false, true)) {
            events.clear()
            messages.clear()
            val (sdk, delegate) = start(true)
            val displayed = shown()
            try {
                delegate.action("shown", displayed)
                val reply = delegate.action("response", displayed, response = "Saved answer")
                Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to false))
                assertTrue((preferences.getValue(PostHogPreferences.SURVEY_PROGRESS) as Map<*, *>).isNotEmpty())
                if (reset) sdk.reset() else delegate.action("closed", displayed)
                shadowOf(Looper.getMainLooper()).idle()
                assertTrue((preferences.getValue(PostHogPreferences.SURVEY_PROGRESS) as? Map<*, *>).isNullOrEmpty())
                val count = events.size
                val stale = delegate.action("response", displayed, 1, "Stale")
                Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
                assertEquals(count, events.size)
                if (reset) assertEquals("hideSurveys", messages.last().first)
            } finally {
                sdk.close()
                preferences.clear()
            }
        }
    }

    @Test
    fun skippedOptionalAnswerAlsoPersistsTheNextQuestion() {
        val (sdk, delegate) = start(true)
        try {
            val displayed = shown()
            delegate.action("shown", displayed)
            val reply = delegate.action("response", displayed)
            Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to false))
        } finally {
            sdk.close()
        }
        val (resumedSdk, _) = start(true)
        try {
            assertEquals(1, shown()["initialQuestionIndex"])
        } finally {
            resumedSdk.close()
            preferences.clear()
        }
    }
}
