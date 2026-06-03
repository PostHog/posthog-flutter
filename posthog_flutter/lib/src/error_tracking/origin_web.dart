// Portions of this file are derived from getsentry/sentry-dart
// Copyright (c) 2020 Sentry
// Licensed under the MIT License: https://github.com/getsentry/sentry-dart/blob/main/LICENSE

import 'package:web/web.dart';

/// request origin, used for browser stacktrace
String get eventOrigin => '${window.location.origin}/';
