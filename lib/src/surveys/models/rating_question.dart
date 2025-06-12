/// Rating scale options for survey questions
/// Each scale represents the number of options (3, 5, 7, or 10)
enum RatingScale {
  threePoint, // 1-3
  fivePoint, // 1-5
  sevenPoint, // 1-7
  tenPoint, // 0-10
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
      case RatingScale.sevenPoint:
        return [1, 2, 3, 4, 5, 6, 7];
      case RatingScale.tenPoint:
        return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    }
  }
}
