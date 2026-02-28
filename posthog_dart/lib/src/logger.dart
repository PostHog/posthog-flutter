/// Logger used internally by PostHog.
class PostHogLogger {
  final String _prefix;
  final void Function(void Function()) _maybeCall;

  PostHogLogger(this._prefix, this._maybeCall);

  void info(Object? message, [Object? arg]) {
    _maybeCall(
        () => print('$_prefix [INFO] $message${arg != null ? ' $arg' : ''}'));
  }

  void warn(Object? message, [Object? arg]) {
    _maybeCall(
        () => print('$_prefix [WARN] $message${arg != null ? ' $arg' : ''}'));
  }

  void error(Object? message, [Object? arg]) {
    _maybeCall(
        () => print('$_prefix [ERROR] $message${arg != null ? ' $arg' : ''}'));
  }

  void critical(Object? message, [Object? arg]) {
    // Critical errors are always logged regardless of debug mode
    print('$_prefix [CRITICAL] $message${arg != null ? ' $arg' : ''}');
  }
}
