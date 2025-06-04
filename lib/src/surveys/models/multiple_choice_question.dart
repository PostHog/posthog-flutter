class PostHogMultipleSurveyQuestion {
  const PostHogMultipleSurveyQuestion({
    required this.question,
    this.description,
    required this.choices,
    this.buttonText,
    this.optional = false,
    this.hasOpenChoice = false,
  });

  final String question;
  final String? description;
  final List<String> choices;
  final String? buttonText;
  final bool? optional;
  final bool? hasOpenChoice;
}
