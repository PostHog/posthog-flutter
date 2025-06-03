/// Rating scale options for survey questions
enum RatingScale {
  threePoint,
  fivePoint,
  sevenPoint,
  tenPoint,
}

/// Display options for rating questions
enum RatingDisplay {
  number,
  emoji,
}

/// Helper to convert rating scale to bounds
extension RatingScaleBounds on RatingScale {
  List<int> get bounds {
    switch (this) {
      case RatingScale.threePoint:
        return [1, 3];
      case RatingScale.sevenPoint:
        return [1, 7];
      case RatingScale.tenPoint:
        return [0, 10];
      case RatingScale.fivePoint:
        return [1, 5];
    }
  }
}
