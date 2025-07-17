/// Rating type for survey questions
enum PostHogDisplaySurveyRatingType {
  number(0),
  emoji(1);

  const PostHogDisplaySurveyRatingType(this.value);
  final int value;

  static PostHogDisplaySurveyRatingType fromInt(int type) {
    return PostHogDisplaySurveyRatingType.values.firstWhere(
      (e) => e.value == type,
      orElse: () => PostHogDisplaySurveyRatingType.number,
    );
  }

  @override
  String toString() => name;
}
