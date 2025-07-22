import 'package:flutter/foundation.dart';
import 'posthog_survey_question_type.dart';
import 'posthog_display_survey_question.dart';
import 'posthog_display_survey_rating_type.dart';

/// Rating question type
@immutable
class PostHogDisplayRatingQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayRatingQuestion({
    required super.question,
    required this.ratingType,
    required this.scaleLowerBound,
    required this.scaleUpperBound,
    required this.lowerBoundLabel,
    required this.upperBoundLabel,
    super.description,
    super.optional,
    super.buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.rating,
        );

  final PostHogDisplaySurveyRatingType ratingType;
  final int scaleLowerBound;
  final int scaleUpperBound;
  final String lowerBoundLabel;
  final String upperBoundLabel;
}
