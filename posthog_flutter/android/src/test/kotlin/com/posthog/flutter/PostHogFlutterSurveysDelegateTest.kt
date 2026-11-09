package com.posthog.flutter

import android.os.Looper
import com.posthog.PostHogBeforeSend
import com.posthog.PostHogInterface
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import com.posthog.android.surveys.PostHogSurveysIntegration
import com.posthog.internal.PostHogPreferences
import com.posthog.internal.PostHogSerializer
import com.posthog.surveys.PostHogDisplaySurvey
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
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class PostHogFlutterSurveysDelegateTest {
    private val context = RuntimeEnvironment.getApplication()
    private val apiKey = "survey-resume-${UUID.randomUUID()}"
    private val events = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val messages = mutableListOf<Pair<String, Any?>>()

    private lateinit var preferences: PostHogPreferences
    private lateinit var integration: PostHogSurveysIntegration
    private lateinit var survey: Survey

    private fun start(
        partial: Boolean,
        drainMainLooper: Boolean = true,
    ): Pair<PostHogInterface, PostHogFlutterSurveysDelegate> {
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
        integration = config.integrations.filterIsInstance<PostHogSurveysIntegration>().single()
        survey =
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
        if (drainMainLooper) shadowOf(Looper.getMainLooper()).idle()
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
    fun detachCancelsQueuedPresentationBeforeReattach() {
        val channel = Mockito.mock(MethodChannel::class.java)
        val delegate = PostHogFlutterSurveysDelegate(channel)
        val survey = PostHogDisplaySurvey("test-survey", "Feedback", emptyList())
        var closed = 0
        delegate.renderSurvey(survey, {}, { _, _, _ -> null }, { closed++ })

        delegate.detachFromEngine()
        assertNull(delegate.channel)
        val reattached = Mockito.mock(MethodChannel::class.java)
        delegate.attachToEngine(reattached)
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(1, closed)
        Mockito.verifyNoInteractions(channel, reattached)
    }

    @Test
    fun renderWithoutEngineReportsClosedInsteadOfKeepingPresentationPending() {
        val channel = Mockito.mock(MethodChannel::class.java)
        val delegate = PostHogFlutterSurveysDelegate(channel)
        delegate.detachFromEngine()
        val survey = PostHogDisplaySurvey("test-survey", "Feedback", emptyList())
        var closed = 0

        delegate.renderSurvey(survey, {}, { _, _, _ -> null }, { closed++ })
        shadowOf(Looper.getMainLooper()).idle()
        delegate.detachFromEngine()

        assertEquals(1, closed)
        Mockito.verifyNoInteractions(channel)
    }

    @Test
    fun detachBeforeShownReleasesNativeReservationWithoutInteractionEvents() {
        val (sdk, delegate) = start(true, drainMainLooper = false)
        try {
            delegate.detachFromEngine()
            val channel = Mockito.mock(MethodChannel::class.java)
            delegate.attachToEngine(channel)
            integration.onSurveysLoaded(listOf(survey))
            shadowOf(Looper.getMainLooper()).idle()

            Mockito.verify(channel).invokeMethod(Mockito.eq("showSurvey"), Mockito.any())
            assertEquals(0, messages.count { it.first == "showSurvey" })
            assertTrue(events.isEmpty())
            assertTrue((preferences.getValue(PostHogPreferences.SURVEY_SEEN) as? Map<*, *>).isNullOrEmpty())
            assertNull(preferences.getValue(PostHogPreferences.LAST_SEEN_SURVEY_DATE))
        } finally {
            sdk.close()
            preferences.clear()
        }
    }

    @Test
    fun detachInvalidatesActionsFromTheOldEngine() {
        val (sdk, delegate) = start(true)
        try {
            val presentation = shown()
            delegate.action("shown", presentation)
            val messageCount = messages.size
            val eventCount = events.size

            delegate.detachFromEngine()

            val stale = delegate.action("response", presentation, response = "Stale")
            Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(eventCount, events.size)
            assertEquals(messageCount, messages.size)
        } finally {
            sdk.close()
            preferences.clear()
        }
    }

    @Test
    fun detachPreservesUnfinishedAnswersWithoutDismissingOrMarkingSeen() {
        for (partial in listOf(true, false)) {
            events.clear()
            messages.clear()
            val (sdk, delegate) = start(partial)
            val presentation = shown()
            try {
                delegate.action("shown", presentation)
                val reply = delegate.action("response", presentation, response = "Saved answer")
                Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to false))
                val progress = assertNotNull(preferences.getValue(PostHogPreferences.SURVEY_PROGRESS))
                val eventCount = events.size
                val lastSeen = preferences.getValue(PostHogPreferences.LAST_SEEN_SURVEY_DATE)
                val seen = (preferences.getValue(PostHogPreferences.SURVEY_SEEN) as? Map<*, *>)?.toMap()

                delegate.detachFromEngine()
                shadowOf(Looper.getMainLooper()).idle()

                assertNull(delegate.channel)
                assertEquals(progress, preferences.getValue(PostHogPreferences.SURVEY_PROGRESS))
                assertEquals(eventCount, events.size)
                assertEquals(0, events.count { it.first == "survey dismissed" })
                assertEquals(seen, preferences.getValue(PostHogPreferences.SURVEY_SEEN))
                if (!partial) assertTrue(seen.isNullOrEmpty())
                assertEquals(lastSeen, preferences.getValue(PostHogPreferences.LAST_SEEN_SURVEY_DATE))
            } finally {
                sdk.close()
            }

            val (resumedSdk, resumedDelegate) = start(partial)
            try {
                val resumed = shown()
                assertEquals(1, resumed["initialQuestionIndex"])
                resumedDelegate.action("shown", resumed)
                resumedDelegate.action("response", resumed, 1, "Final answer")
                val completed = events.last { it.first == "survey sent" }.second
                assertEquals("Saved answer", completed["\$survey_response_first"])
                assertEquals("Final answer", completed["\$survey_response_second"])
                assertEquals(true, completed["\$survey_completed"])
            } finally {
                resumedSdk.close()
                preferences.clear()
            }
        }
    }

    @Test
    fun repeatedSetupDoesNotRedisplayAnActiveSurvey() {
        val (sdk, delegate) = start(true)
        try {
            val presentation = shown()
            delegate.action("shown", presentation)
            delegate.action("response", presentation, response = "Saved answer")
            val messageCount = messages.size
            val eventCount = events.size

            delegate.attachToEngine(assertNotNull(delegate.channel))
            shadowOf(Looper.getMainLooper()).idle()

            assertEquals(messageCount, messages.size)
            assertEquals(eventCount, events.size)
            val reply = delegate.action("response", presentation, 1, "Final answer")
            Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to true))
        } finally {
            sdk.close()
            preferences.clear()
        }
    }

    @Test
    fun reattachContinuesTheSameUnfinishedAttemptAtTheNextQuestion() {
        for (partial in listOf(true, false)) {
            events.clear()
            messages.clear()
            val (sdk, delegate) = start(partial)
            try {
                val first = shown()
                delegate.action("shown", first)
                delegate.action("response", first, response = "Saved answer")
                val eventCount = events.size
                val channel = Mockito.mock(MethodChannel::class.java)
                Mockito
                    .doAnswer { call ->
                        messages.add(call.getArgument<String>(0) to call.getArgument<Any?>(1))
                        null
                    }.`when`(channel)
                    .invokeMethod(Mockito.anyString(), Mockito.any())

                delegate.detachFromEngine()
                delegate.attachToEngine(channel)
                delegate.detachFromEngine()
                delegate.attachToEngine(channel)
                shadowOf(Looper.getMainLooper()).idle()

                val resumed = shown()
                assertEquals(1, resumed["initialQuestionIndex"])
                assertNotEquals(first["presentationId"], resumed["presentationId"])
                assertEquals(2, messages.count { it.first == "showSurvey" })
                delegate.action("shown", resumed)
                assertEquals(eventCount, events.size)
                val stale = delegate.action("response", first, 1, "Stale")
                Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
                val reply = delegate.action("response", resumed, 1, "Final answer")
                Mockito.verify(reply).success(mapOf("nextIndex" to 1, "isSurveyCompleted" to true))
                val completed = events.last { it.first == "survey sent" }.second
                assertEquals("Saved answer", completed["\$survey_response_first"])
                assertEquals("Final answer", completed["\$survey_response_second"])
                assertEquals(true, completed["\$survey_completed"])
                if (partial) {
                    val firstResponse = events.first { it.first == "survey sent" }.second
                    assertEquals(firstResponse["\$survey_submission_id"], completed["\$survey_submission_id"])
                }
                delegate.detachFromEngine()
                assertEquals(0, events.count { it.first == "survey dismissed" })
                assertTrue((preferences.getValue(PostHogPreferences.SURVEY_PROGRESS) as? Map<*, *>).isNullOrEmpty())
            } finally {
                sdk.close()
                preferences.clear()
            }
        }
    }

    @Test
    fun resetOrCloseWhileDetachedPreventsReattachFromRevivingThePresentation() {
        for (reset in listOf(true, false)) {
            events.clear()
            messages.clear()
            val (sdk, delegate) = start(true)
            try {
                val presentation = shown()
                delegate.action("shown", presentation)
                delegate.action("response", presentation, response = "Saved answer")
                delegate.detachFromEngine()

                if (reset) sdk.reset() else sdk.close()
                val channel = Mockito.mock(MethodChannel::class.java)
                delegate.attachToEngine(channel)
                shadowOf(Looper.getMainLooper()).idle()

                Mockito.verify(channel, Mockito.never()).invokeMethod(Mockito.eq("showSurvey"), Mockito.any())
                val stale = delegate.action("response", presentation, 1, "Stale")
                Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
                assertEquals(0, events.count { it.first == "survey dismissed" })
            } finally {
                sdk.close()
                preferences.clear()
            }
        }
    }

    @Test
    fun closeHidesSurveyBeforeChannelIsReleasedAndRejectsOldActions() {
        val (sdk, delegate) = start(true)
        val presentation = shown()
        delegate.action("shown", presentation)

        sdk.close()
        delegate.detachFromEngine()

        assertNull(delegate.channel)
        assertEquals("hideSurveys", messages.last().first)
        val count = events.size
        val stale = delegate.action("response", presentation, response = "Stale")
        Mockito.verify(stale).error(Mockito.eq("SurveyInvalidated"), Mockito.anyString(), Mockito.isNull())
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(count, events.size)
        assertEquals(1, messages.count { it.first == "hideSurveys" })
        preferences.clear()
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
