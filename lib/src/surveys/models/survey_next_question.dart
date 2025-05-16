/// Represents the next question to show in a survey
class PostHogSurveyNextQuestion {
  const PostHogSurveyNextQuestion({
    required this.questionIndex,
    required this.isSurveyCompleted,
  });

  final int questionIndex;
  final bool isSurveyCompleted;
}
