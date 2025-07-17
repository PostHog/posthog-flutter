import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';
import 'posthog_display_survey_question.dart';

/// choice question type
@immutable
class PostHogDisplayChoiceQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayChoiceQuestion({
    required super.question,
    required this.choices,
    required this.isMultipleChoice,
    this.hasOpenChoice = false,
    this.shuffleOptions = false,
    super.description,
    super.optional,
    super.buttonText,
  }) : super(
          type: isMultipleChoice
              ? PostHogSurveyQuestionType.multipleChoice
              : PostHogSurveyQuestionType.singleChoice,
        );

  final List<String> choices;
  final bool isMultipleChoice;
  final bool hasOpenChoice;
  final bool shuffleOptions;
}
