import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';

/// Base class for all survey questions
@immutable
abstract class PostHogDisplaySurveyQuestion {
  const PostHogDisplaySurveyQuestion({
    required this.type,
    required this.question,
    this.description,
    this.optional = false,
    this.buttonText,
  });

  final PostHogSurveyQuestionType type;
  final String question;
  final String? description;
  final bool optional;
  final String? buttonText;
}
