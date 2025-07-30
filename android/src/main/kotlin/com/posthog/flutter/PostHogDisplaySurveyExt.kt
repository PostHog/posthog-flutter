package com.posthog.flutter

import com.posthog.surveys.PostHogDisplayChoiceQuestion
import com.posthog.surveys.PostHogDisplayLinkQuestion
import com.posthog.surveys.PostHogDisplayOpenQuestion
import com.posthog.surveys.PostHogDisplayRatingQuestion
import com.posthog.surveys.PostHogDisplaySurvey
import com.posthog.surveys.PostHogDisplaySurveyQuestion

// Convert the survey object to a map for communication with the Dart layer
// Native platform model -> Map -> Dart model
fun PostHogDisplaySurvey.toMap(): Map<String, Any?> {
    val map =
        mutableMapOf<String, Any?>(
            "id" to id,
            "name" to name,
            "questions" to
                questions.map { question: PostHogDisplaySurveyQuestion ->
                    val questionMap =
                        mutableMapOf<String, Any?>(
                            "question" to question.question,
                            "isOptional" to question.isOptional,
                        )

                    questionMap["questionDescription"] = question.questionDescription
                    questionMap["buttonText"] = question.buttonText

                    // Add question type-specific properties
                    when (question) {
                        is PostHogDisplayLinkQuestion -> {
                            questionMap["type"] = "link"
                            questionMap["link"] = question.link
                        }
                        is PostHogDisplayRatingQuestion -> {
                            questionMap["type"] = "rating"
                            questionMap["ratingType"] = question.ratingType.value
                            questionMap["scaleLowerBound"] = question.scaleLowerBound
                            questionMap["scaleUpperBound"] = question.scaleUpperBound
                            questionMap["lowerBoundLabel"] = question.lowerBoundLabel
                            questionMap["upperBoundLabel"] = question.upperBoundLabel
                        }
                        is PostHogDisplayChoiceQuestion -> {
                            questionMap["type"] = if (question.isMultipleChoice) "multiple_choice" else "single_choice"
                            questionMap["choices"] = question.choices
                            questionMap["hasOpenChoice"] = question.hasOpenChoice
                            questionMap["shuffleOptions"] = question.shuffleOptions
                        }
                        is PostHogDisplayOpenQuestion -> {
                            questionMap["type"] = "open"
                        }
                        else -> {
                            questionMap["type"] = "open"
                        }
                    }

                    questionMap
                },
        )

    // Add appearance if available
    appearance?.let { app ->
        map["appearance"] =
            mapOf(
                "backgroundColor" to app.backgroundColor,
                "submitButtonColor" to app.submitButtonColor,
                "submitButtonText" to app.submitButtonText,
                "submitButtonTextColor" to app.submitButtonTextColor,
                "descriptionTextColor" to app.descriptionTextColor,
                "ratingButtonColor" to app.ratingButtonColor,
                "ratingButtonActiveColor" to app.ratingButtonActiveColor,
                "borderColor" to app.borderColor,
                "placeholder" to app.placeholder,
                "displayThankYouMessage" to app.displayThankYouMessage,
                "thankYouMessageHeader" to app.thankYouMessageHeader,
                "thankYouMessageDescription" to app.thankYouMessageDescription,
                "thankYouMessageDescriptionContentType" to app.thankYouMessageDescriptionContentType?.name,
            )
    }

    // Add dates if available (convert to milliseconds since epoch)
    startDate?.let { date ->
        map["startDate"] = date.time
    }

    endDate?.let { date ->
        map["endDate"] = date.time
    }

    return map
}
