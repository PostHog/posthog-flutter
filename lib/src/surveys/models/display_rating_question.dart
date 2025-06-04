class PostHogDisplayRatingQuestion {
  const PostHogDisplayRatingQuestion({
    required this.question,
    this.description,
    this.buttonText,
    this.optional = false,
    required this.scale,
    required this.display,
    this.lowerBoundLabel,
    this.upperBoundLabel,
  });

  final String question;
  final String? description;
  final String? buttonText;
  final bool optional;
  final String scale;
  final String display;
  final String? lowerBoundLabel;
  final String? upperBoundLabel;
}
