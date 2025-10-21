class PropertyNormalizer {
  /// Normalizes a map of properties to ensure they are serializable through method channels.
  ///
  /// Unsupported types are converted to strings using toString().
  /// Nested maps and lists are recursively normalized.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> properties) {
    return properties
        .map((key, value) => MapEntry(key.toString(), _normalizeValue(value)));
  }

  /// Normalizes a single value to ensure it's serializable through method channels.
  static dynamic _normalizeValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is bool || value is String || value is double || value is int) {
      return value;
    } else if (value is List<dynamic>) {
      return value.map((e) => _normalizeValue(e)).toList();
    } else if (value is Map) {
      return normalize(value);
    } else {
      return value.toString();
    }
  }
}
