import 'posthog_display_survey.dart';

/// Called when a survey is shown to the user
typedef OnSurveyShown = void Function(PostHogDisplaySurvey survey);

/// Called when a user responds to a survey question
typedef OnSurveyResponse = Future<PostHogSurveyNextQuestion> Function(
  PostHogDisplaySurvey survey,
  int questionIndex,
  Object? response,
);

/// Called when a survey is closed
typedef OnSurveyClosed = void Function(PostHogDisplaySurvey survey);

/// Represents the next question to show in a survey
class PostHogSurveyNextQuestion {
  const PostHogSurveyNextQuestion({
    required this.questionIndex,
    required this.isSurveyCompleted,
  });

  final int questionIndex;
  final bool isSurveyCompleted;
}
