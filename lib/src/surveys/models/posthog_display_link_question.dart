import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';
import 'posthog_display_survey_question.dart';

/// Link question type
@immutable
class PostHogDisplayLinkQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayLinkQuestion({
    required super.question,
    required this.link,
    super.description,
    super.optional,
    super.buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.link,
        );

  final String link;
}
