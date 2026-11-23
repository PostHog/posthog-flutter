import 'package:flutter/widgets.dart';

/// Whether the app is in the foreground. A null lifecycle state means none was
/// delivered yet, which is treated as foreground.
bool get isAppInForeground {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}
