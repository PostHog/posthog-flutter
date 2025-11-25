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
import com.posthog.surveys.PostHogSurveysDelegate
import io.flutter.plugin.common.MethodChannel

/**
 * Separate surveys delegate to avoid class loading issues in the main plugin
 */
class PostHogFlutterSurveysDelegate(
    private val channel: MethodChannel,
) : PostHogSurveysDelegate {
    private var currentSurvey: PostHogDisplaySurvey? = null
    private var onSurveyShownCallback: OnPostHogSurveyShown? = null
    private var onSurveyResponseCallback: OnPostHogSurveyResponse? = null
    private var onSurveyClosedCallback: OnPostHogSurveyClosed? = null

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

        // Convert survey to map and send to Flutter
        invokeFlutterMethod("showSurvey", survey.toMap())
    }

    override fun cleanupSurveys() {
        currentSurvey = null
        onSurveyShownCallback = null
        onSurveyResponseCallback = null
        onSurveyClosedCallback = null
    }

    fun handleSurveyAction(
        action: String,
        payload: Map<String, Any>?,
        result: MethodChannel.Result,
    ) {
        val survey = currentSurvey
        if (survey == null) {
            result.error("InvalidArguments", "No active survey", null)
            return
        }

        when (action) {
            "shown" -> {
                onSurveyShownCallback?.invoke(survey)
            }
            "response" -> {
                val index = payload?.get("index") as? Int
                val responsePayload = payload?.get("response")

                if (index != null && responsePayload != null && index < survey.questions.size) {
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
                                    // Multiple choice: accept array directly from Flutter
                                    val selectedOptions = responsePayload as? List<*>
                                    val stringOptions = selectedOptions?.mapNotNull { it as? String }
                                    PostHogSurveyResponse.MultipleChoice(stringOptions ?: emptyList())
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
                currentSurvey = null
                onSurveyShownCallback = null
                onSurveyResponseCallback = null
                onSurveyClosedCallback = null
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
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod(method, arguments)
        }
    }
}
