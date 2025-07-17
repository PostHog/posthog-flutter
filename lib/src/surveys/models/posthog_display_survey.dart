import 'package:flutter/foundation.dart';
import 'posthog_display_survey_question.dart';
import 'posthog_display_survey_rating_type.dart';
import 'posthog_display_open_question.dart';
import 'posthog_display_link_question.dart';
import 'posthog_display_rating_question.dart';
import 'posthog_display_choice_question.dart';
import 'posthog_display_survey_appearance.dart';

/// Main survey model containing metadata and questions
@immutable
class PostHogDisplaySurvey {
  // Convert back from survey dictionary to a Dart object
  // Native platform model -> Dictionary -> Dart model
  factory PostHogDisplaySurvey.fromDict(Map<String, dynamic> dict) {
    final questions = (dict['questions'] as List).map((q) {
      final type = q['type'] as String;
      final question = q['question'] as String;
      final optional = q['isOptional'] as bool;
      final questionDescription = q['questionDescription'] as String?;
      final buttonText = q['buttonText'] as String?;

      switch (type) {
        case 'link':
          return PostHogDisplayLinkQuestion(
            question: question,
            link: q['link'] as String,
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'rating':
          return PostHogDisplayRatingQuestion(
            question: question,
            ratingType:
                PostHogDisplaySurveyRatingType.fromInt(q['ratingType'] as int),
            scaleLowerBound: q['scaleLowerBound'] as int,
            scaleUpperBound: q['scaleUpperBound'] as int,
            lowerBoundLabel: q['lowerBoundLabel'] as String,
            upperBoundLabel: q['upperBoundLabel'] as String,
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'multiple_choice':
        case 'single_choice':
          return PostHogDisplayChoiceQuestion(
            question: question,
            choices: (q['choices'] as List).cast<String>(),
            isMultipleChoice: type == 'multiple_choice',
            hasOpenChoice: q['hasOpenChoice'] as bool,
            shuffleOptions: q['shuffleOptions'] as bool,
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'open':
        default:
          return PostHogDisplayOpenQuestion(
            question: question,
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
      }
    }).toList();

    PostHogDisplaySurveyAppearance? appearance;
    if (dict['appearance'] != null) {
      final a = Map<String, dynamic>.from(dict['appearance'] as Map);
      appearance = PostHogDisplaySurveyAppearance(
        fontFamily: a['fontFamily'] as String?,
        backgroundColor: a['backgroundColor'] as String?,
        borderColor: a['borderColor'] as String?,
        submitButtonColor: a['submitButtonColor'] as String?,
        submitButtonText: a['submitButtonText'] as String?,
        submitButtonTextColor: a['submitButtonTextColor'] as String?,
        descriptionTextColor: a['descriptionTextColor'] as String?,
        ratingButtonColor: a['ratingButtonColor'] as String?,
        ratingButtonActiveColor: a['ratingButtonActiveColor'] as String?,
        placeholder: a['placeholder'] as String?,
        displayThankYouMessage: a['displayThankYouMessage'] as bool? ?? true,
        thankYouMessageHeader: a['thankYouMessageHeader'] as String?,
        thankYouMessageDescription: a['thankYouMessageDescription'] as String?,
        thankYouMessageCloseButtonText:
            a['thankYouMessageCloseButtonText'] as String?,
      );
    }

    DateTime? startDate;
    if (dict['startDate'] != null) {
      startDate = DateTime.fromMillisecondsSinceEpoch(dict['startDate'] as int);
    }

    DateTime? endDate;
    if (dict['endDate'] != null) {
      endDate = DateTime.fromMillisecondsSinceEpoch(dict['endDate'] as int);
    }

    return PostHogDisplaySurvey(
      id: dict['id'] as String,
      name: dict['name'] as String,
      questions: questions,
      appearance: appearance,
      startDate: startDate,
      endDate: endDate,
    );
  }

  const PostHogDisplaySurvey({
    required this.id,
    required this.name,
    required this.questions,
    this.appearance,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String name;
  final List<PostHogDisplaySurveyQuestion> questions;
  final PostHogDisplaySurveyAppearance? appearance;
  final DateTime? startDate;
  final DateTime? endDate;
}
