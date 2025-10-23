import 'dart:typed_data';

class PropertyNormalizer {
  /// Normalizes a map of properties to ensure they are serializable through method channels.
  ///
  /// Unsupported types are converted to strings using toString().
  /// Nested maps and lists are recursively normalized.
  /// Nulls are stripped.
  static Map<String, Object?> normalize(Map<String, Object?> properties) {
    return Map.fromEntries(
      properties.entries
          .map((entry) => MapEntry(entry.key, _normalizeValue(entry.value)))
          .where((entry) => entry.value != null),
    );
  }

  /// Normalizes a single value to ensure it's serializable through method channels.
  static Object? _normalizeValue(Object? value) {
    if (_isSupported(value)) {
      return value;
    } else if (value is List) {
      return value.map((e) => _normalizeValue(e)).toList();
    } else if (value is Set) {
      return value.map((e) => _normalizeValue(e)).toList();
    } else if (value is Map) {
      return Map<String, Object?>.fromEntries(
        value.entries
            .map((entry) =>
                MapEntry(entry.key.toString(), _normalizeValue(entry.value)))
            .where((entry) => entry.value != null),
      );
    } else {
      return value.toString();
    }
  }

  /// Checks if a value is natively supported by StandardMessageCodec
  /// see: https://api.flutter.dev/flutter/services/StandardMessageCodec-class.html
  static bool _isSupported(Object? value) {
    return value == null ||
        value is bool ||
        value is String ||
        value is num ||
        value is Uint8List ||
        value is Int32List ||
        value is Int64List ||
        value is Float64List;
  }
}
