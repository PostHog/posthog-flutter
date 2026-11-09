package com.posthog.flutter

import android.os.Handler
import android.os.Looper
import com.posthog.surveys.OnPostHogSurveyClosed
import com.posthog.surveys.OnPostHogSurveyResponse
import com.posthog.surveys.OnPostHogSurveyShown
import com.posthog.surveys.PostHogDisplayChoiceQuestion
import com.posthog.surveys.PostHogDisplayLinkQuestion
import com.posthog.surveys.PostHogDisplayOpenQuestion
import com.posthog.surveys.PostHogDisplayRatingQuestion
import com.posthog.surveys.PostHogDisplaySurvey
import com.posthog.surveys.PostHogDisplaySurveyQuestion
import com.posthog.surveys.PostHogNextSurveyQuestion
import com.posthog.surveys.PostHogSurveyResponse
import com.posthog.surveys.PostHogSurveysResumeAwareDelegate
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Separate surveys delegate to avoid class loading issues in the main plugin
 */
class PostHogFlutterSurveysDelegate(
    channel: MethodChannel,
) : PostHogSurveysResumeAwareDelegate {
    // Native setup keeps the first delegate; its engine channel can detach independently.
    @Volatile
    internal var channel: MethodChannel? = channel
        private set

    override val supportsSurveyResume: Boolean = true

    @Volatile
    private var presentationId: String? = null
    private var currentSurvey: PostHogDisplaySurvey? = null
    private var onSurveyShownCallback: OnPostHogSurveyShown? = null
    private var onSurveyResponseCallback: OnPostHogSurveyResponse? = null
    private var onSurveyClosedCallback: OnPostHogSurveyClosed? = null
    private var hasBeenShown = false
    private var isSurveyCompleted = false

    override fun renderSurvey(
        survey: PostHogDisplaySurvey,
        onSurveyShown: OnPostHogSurveyShown,
        onSurveyResponse: OnPostHogSurveyResponse,
        onSurveyClosed: OnPostHogSurveyClosed,
    ) {
        currentSurvey = survey
        onSurveyShownCallback = onSurveyShown
        onSurveyResponseCallback = onSurveyResponse
        onSurveyClosedCallback = onSurveyClosed
        hasBeenShown = false
        isSurveyCompleted = false
        presentSurvey()
    }

    internal fun attachToEngine(channel: MethodChannel) {
        this.channel = channel
        if (hasBeenShown && presentationId == null) {
            presentSurvey()
        }
    }

    private fun presentSurvey() {
        val survey = currentSurvey ?: return
        val presentation = UUID.randomUUID().toString()
        presentationId = presentation
        Handler(Looper.getMainLooper()).post {
            if (presentationId == presentation) {
                val target = channel
                if (target == null) {
                    detachFromEngine()
                } else {
                    target.invokeMethod("showSurvey", survey.toMap() + ("presentationId" to presentation))
                }
            }
        }
    }

    internal fun detachFromEngine() {
        channel = null
        presentationId = null
        // Closing an unfinished, shown survey deletes native progress and records a dismissal.
        // Keep its callbacks (not its engine) so reattach can continue the same attempt.
        if (hasBeenShown && !isSurveyCompleted) {
            return
        }
        val survey = currentSurvey
        val onClosed = onSurveyClosedCallback
        cleanupSurveys()
        if (survey != null) {
            onClosed?.invoke(survey)
        }
    }

    override fun cleanupSurveys() {
        presentationId = null
        currentSurvey = null
        onSurveyShownCallback = null
        onSurveyResponseCallback = null
        onSurveyClosedCallback = null
        hasBeenShown = false
        isSurveyCompleted = false
        invokeFlutterMethod("hideSurveys")
    }

    fun handleSurveyAction(
        action: String,
        payload: Map<String, Any>?,
        result: MethodChannel.Result,
    ) {
        val survey = currentSurvey
        if (survey == null || presentationId == null || payload?.get("presentationId") != presentationId) {
            result.error("SurveyInvalidated", "Survey presentation is no longer active", null)
            return
        }

        when (action) {
            "shown" -> {
                if (!hasBeenShown) {
                    hasBeenShown = true
                    onSurveyShownCallback?.invoke(survey)
                }
            }

            "response" -> {
                val index = payload?.get("index") as? Int
                val responsePayload = payload?.get("response")

                if (index != null && index in survey.questions.indices) {
                    val question = survey.questions[index]

                    // Create PostHogSurveyResponse based on question type
                    val surveyResponse =
                        when (question) {
                            is PostHogDisplayLinkQuestion -> {
                                // For link questions
                                val boolValue = responsePayload as? Boolean ?: false
                                PostHogSurveyResponse.Link(boolValue)
                            }

                            is PostHogDisplayRatingQuestion -> {
                                // For rating questions
                                val ratingValue = responsePayload as? Int
                                PostHogSurveyResponse.Rating(ratingValue)
                            }

                            is PostHogDisplayChoiceQuestion -> {
                                // For single/multiple choice questions
                                if (question.isMultipleChoice) {
                                    // Multiple choice: accept array directly from Flutter.
                                    // Null and empty both mean the optional question was skipped.
                                    val selectedOptions = responsePayload as? List<*>
                                    val stringOptions = selectedOptions?.mapNotNull { it as? String }
                                    PostHogSurveyResponse.MultipleChoice(
                                        stringOptions?.takeIf { it.isNotEmpty() },
                                    )
                                } else {
                                    // Single choice: Flutter sends as a list with one element
                                    val selectedOptions = responsePayload as? List<*>
                                    val firstOption = selectedOptions?.firstOrNull() as? String
                                    PostHogSurveyResponse.SingleChoice(firstOption)
                                }
                            }

                            else -> {
                                // Default to open text question
                                val textValue = responsePayload as? String
                                PostHogSurveyResponse.Text(textValue)
                            }
                        }

                    // Call the callback with the constructed response
                    onSurveyResponseCallback?.invoke(survey, index, surveyResponse)?.let { nextQuestion ->
                        currentSurvey = survey.copy(initialQuestionIndex = nextQuestion.questionIndex)
                        isSurveyCompleted = nextQuestion.isSurveyCompleted
                        result.success(
                            mapOf(
                                "nextIndex" to nextQuestion.questionIndex,
                                "isSurveyCompleted" to nextQuestion.isSurveyCompleted,
                            ),
                        )
                        return
                    }
                    result.success(null)
                    return
                }
            }

            "closed" -> {
                onSurveyClosedCallback?.invoke(survey)
                // Clear the callbacks after survey is closed
                presentationId = null
                currentSurvey = null
                onSurveyShownCallback = null
                onSurveyResponseCallback = null
                onSurveyClosedCallback = null
                hasBeenShown = false
                isSurveyCompleted = false
            }
        }

        result.success(null)
    }

    /**
     * Invoke a Flutter method on the main/UI thread
     */
    private fun invokeFlutterMethod(
        method: String,
        arguments: Any? = null,
    ) {
        // close() releases the channel after native cleanup, so hide before returning on main.
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel?.invokeMethod(method, arguments)
        } else {
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod(method, arguments)
            }
        }
    }
}
