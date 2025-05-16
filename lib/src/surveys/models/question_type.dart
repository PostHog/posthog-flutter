/// The type of survey question
enum PostHogSurveyQuestionType {
  open('open'),
  multipleChoice('multiple_choice'),
  singleChoice('single_choice'),
  rating('rating'),
  link('link');

  const PostHogSurveyQuestionType(this.value);
  final String value;

  static PostHogSurveyQuestionType fromString(String type) {
    return PostHogSurveyQuestionType.values.firstWhere(
      (e) => e.value == type.toLowerCase(),
      orElse: () => PostHogSurveyQuestionType.open,
    );
  }

  @override
  String toString() => value;
}
