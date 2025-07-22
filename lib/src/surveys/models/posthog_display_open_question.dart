import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';
import 'posthog_display_survey_question.dart';

/// Open text question type
@immutable
class PostHogDisplayOpenQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayOpenQuestion({
    required super.question,
    super.description,
    super.optional,
    super.buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.openText,
        );
}
