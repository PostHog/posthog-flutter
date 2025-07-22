#if os(iOS)
    import Foundation
    import PostHog

    extension PostHogDisplaySurvey {
        // Convert the survey object to a dictionary for communication with the Dart layer
        // Native platform model -> Dictionary -> Dart model
        func toDict() -> [String: Any] {
            var dict: [String: Any] = [
                "id": id,
                "name": name,
                "questions": questions.map { question -> [String: Any] in
                    var questionDict: [String: Any] = [
                        "question": question.question,
                        "isOptional": question.isOptional,
                    ]
                    if let desc = question.questionDescription {
                        questionDict["questionDescription"] = desc
                    }
                    if let buttonText = question.buttonText {
                        questionDict["buttonText"] = buttonText
                    }

                    // Add question type-specific properties
                    switch question {
                    case let linkQuestion as PostHogDisplayLinkQuestion:
                        questionDict["type"] = "link"
                        questionDict["link"] = linkQuestion.link
                    case let ratingQuestion as PostHogDisplayRatingQuestion:
                        questionDict["type"] = "rating"
                        questionDict["ratingType"] = ratingQuestion.ratingType.rawValue
                        questionDict["scaleLowerBound"] = ratingQuestion.scaleLowerBound
                        questionDict["scaleUpperBound"] = ratingQuestion.scaleUpperBound
                        questionDict["lowerBoundLabel"] = ratingQuestion.lowerBoundLabel
                        questionDict["upperBoundLabel"] = ratingQuestion.upperBoundLabel
                    case let choiceQuestion as PostHogDisplayChoiceQuestion:
                        questionDict["type"] = choiceQuestion.isMultipleChoice ? "multiple_choice" : "single_choice"
                        questionDict["choices"] = choiceQuestion.choices
                        questionDict["hasOpenChoice"] = choiceQuestion.hasOpenChoice
                        questionDict["shuffleOptions"] = choiceQuestion.shuffleOptions
                    default:
                        questionDict["type"] = "open"
                    }

                    return questionDict
                },
            ]

            if let appearance = appearance {
                var appearanceDict: [String: Any] = [:]
                if let fontFamily = appearance.fontFamily {
                    appearanceDict["fontFamily"] = fontFamily
                }
                if let backgroundColor = appearance.backgroundColor {
                    appearanceDict["backgroundColor"] = backgroundColor
                }
                if let borderColor = appearance.borderColor {
                    appearanceDict["borderColor"] = borderColor
                }
                if let submitButtonColor = appearance.submitButtonColor {
                    appearanceDict["submitButtonColor"] = submitButtonColor
                }
                if let submitButtonText = appearance.submitButtonText {
                    appearanceDict["submitButtonText"] = submitButtonText
                }
                if let submitButtonTextColor = appearance.submitButtonTextColor {
                    appearanceDict["submitButtonTextColor"] = submitButtonTextColor
                }
                if let descriptionTextColor = appearance.descriptionTextColor {
                    appearanceDict["descriptionTextColor"] = descriptionTextColor
                }
                if let ratingButtonColor = appearance.ratingButtonColor {
                    appearanceDict["ratingButtonColor"] = ratingButtonColor
                }
                if let ratingButtonActiveColor = appearance.ratingButtonActiveColor {
                    appearanceDict["ratingButtonActiveColor"] = ratingButtonActiveColor
                }
                if let placeholder = appearance.placeholder {
                    appearanceDict["placeholder"] = placeholder
                }
                appearanceDict["displayThankYouMessage"] = appearance.displayThankYouMessage
                if let thankYouMessageHeader = appearance.thankYouMessageHeader {
                    appearanceDict["thankYouMessageHeader"] = thankYouMessageHeader
                }
                if let thankYouMessageDescription = appearance.thankYouMessageDescription {
                    appearanceDict["thankYouMessageDescription"] = thankYouMessageDescription
                }
                if let thankYouMessageCloseButtonText = appearance.thankYouMessageCloseButtonText {
                    appearanceDict["thankYouMessageCloseButtonText"] = thankYouMessageCloseButtonText
                }
                dict["appearance"] = appearanceDict
            }

            if let startDate = startDate {
                dict["startDate"] = Int64(startDate.timeIntervalSince1970 * 1000) // to milliseconds since epoch
            }
            if let endDate = endDate {
                dict["endDate"] = Int64(endDate.timeIntervalSince1970 * 1000) // to milliseconds since epoch
            }

            return dict
        }
    }
#endif
