import 'posthog_display_survey.dart';
import 'survey_next_question.dart';

/// Called when a survey is shown to the user
typedef OnSurveyShown = void Function(PostHogDisplaySurvey survey);

/// Called when a user responds to a survey question
typedef OnSurveyResponse = Future<PostHogSurveyNextQuestion> Function(
  PostHogDisplaySurvey survey,
  int questionIndex,
  String response,
);

/// Called when a survey is closed
typedef OnSurveyClosed = void Function(PostHogDisplaySurvey survey);
