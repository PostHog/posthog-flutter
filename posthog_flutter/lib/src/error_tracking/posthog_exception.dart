// ignore: unnecessary_import
import 'package:meta/meta.dart';

/// A wrapper exception that carries PostHog-specific metadata
@internal
class PostHogException implements Exception {
  /// The original exception/error that was wrapped
  final Object source;
  final String mechanism;
  final bool handled;

  const PostHogException({
    required this.source,
    required this.mechanism,
    this.handled = false,
  });
}
