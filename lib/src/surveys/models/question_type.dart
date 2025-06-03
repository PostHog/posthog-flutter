/// The type of survey question
enum PostHogSurveyQuestionType {
  openText('open_text'),
  multipleChoice('multiple_choice'),
  singleChoice('single_choice'),
  rating('rating'),
  link('link'),
  unimplemented('unimplemented');

  const PostHogSurveyQuestionType(this.value);
  final String value;

  static PostHogSurveyQuestionType fromString(String type) {
    return PostHogSurveyQuestionType.values.firstWhere(
      (e) => e.value == type.toLowerCase(),
      orElse: () => PostHogSurveyQuestionType.unimplemented,
    );
  }

  @override
  String toString() => value;
}
