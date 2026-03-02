/// Content type for text-based survey elements
enum PostHogDisplaySurveyTextContentType {
  /// Content should be rendered as HTML
  html(0),

  /// Content should be rendered as plain text
  text(1);

  const PostHogDisplaySurveyTextContentType(this.value);

  final int value;

  /// Create from raw int value
  static PostHogDisplaySurveyTextContentType fromInt(int value) {
    return PostHogDisplaySurveyTextContentType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PostHogDisplaySurveyTextContentType.text, // Default to text
    );
  }
}
