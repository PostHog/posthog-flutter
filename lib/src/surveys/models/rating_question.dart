/// Rating scale options for survey questions
enum RatingScale {
  threePoint,
  fivePoint,
  oneToFive,
  oneToTen,
}

/// Display options for rating questions
enum RatingDisplay {
  number,
  emoji,
}

/// Helper to convert rating scale to bounds
extension RatingScaleBounds on RatingScale {
  List<int> get ratingRange {
    switch (this) {
      case RatingScale.threePoint:
        return [1, 2, 3];
      case RatingScale.fivePoint:
        return [1, 2, 3, 4, 5];
      case RatingScale.oneToFive:
        return [1, 2, 3, 4, 5];
      case RatingScale.oneToTen:
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    }
  }
}
