// Portions of this file are derived from getsentry/sentry-dart by Sentry
// Licensed under the MIT License

import 'package:web/web.dart';

/// request origin, used for browser stacktrace
String get eventOrigin => '${window.location.origin}/';
