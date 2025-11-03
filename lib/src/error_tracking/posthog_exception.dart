/// A wrapper exception that carries PostHog-specific metadata
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

  @override
  String toString() {
    return 'PostHogException: ${source.toString()}';
  }
}
