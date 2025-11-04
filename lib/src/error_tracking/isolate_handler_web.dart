/// Web platform stub implementation of isolate error handling
/// Isolates are not available on web, so this is a no-op implementation
class IsolateErrorHandler {
  /// Add error listener to current isolate (no-op on web)
  void addErrorListener(Function(dynamic) onError) {
    // No-op: Isolates are not available on web
  }

  /// Remove error listener and clean up (no-op on web)
  void removeErrorListener() {
    // No-op: Isolates are not available on web
  }

  /// Check if error listener is active (always false on web)
  bool get isActive => false;
}
