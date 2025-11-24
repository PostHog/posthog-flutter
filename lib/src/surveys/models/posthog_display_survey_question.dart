import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';
import 'posthog_display_survey_text_content_type.dart';

/// Base class for all survey questions
@immutable
abstract class PostHogDisplaySurveyQuestion {
  const PostHogDisplaySurveyQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.description,
    this.descriptionContentType = PostHogDisplaySurveyTextContentType.text,
    this.optional = false,
    this.buttonText,
  });

  final String id;
  final PostHogSurveyQuestionType type;
  final String question;
  final String? description;
  final PostHogDisplaySurveyTextContentType descriptionContentType;
  final bool optional;
  final String? buttonText;
}
