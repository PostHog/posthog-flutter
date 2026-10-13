import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'core/logger.dart';
import 'core/utils/utils.dart';
import 'util/logging.dart';
import 'utils/property_normalizer.dart';

/// The exception steps recorded on desktop (Windows/Linux), attached to every
/// `$exception` captured there as `$exception_steps`.
///
/// A FIFO bounded by a UTF-8 byte budget: the oldest steps are evicted to make
/// room for a new one, and a step larger than the whole budget is rejected.
/// Steps live in memory only, as desktop captures no crashes that would be
/// reported on the next launch.
class ExceptionStepsBuffer {
  ExceptionStepsBuffer({required int maxBytes}) : _maxBytes = max(0, maxBytes);

  static const _messageKey = r'$message';
  static const _timestampKey = r'$timestamp';

  /// Reports the values a step sends as their string, in debug builds.
  static final _logger = CoreLogger((log) {
    if (kDebugMode) log();
  });

  final int _maxBytes;
  final _entries = ListQueue<({Map<String, Object?> step, int bytes})>();
  int _totalBytes = 0;

  /// The buffered steps, oldest first.
  List<Map<String, Object?>> get steps =>
      [for (final entry in _entries) entry.step];

  /// Records a step describing [message], stamped with the current time.
  ///
  /// The reserved `$message` and `$timestamp` keys of [properties] are
  /// ignored. The step is normalized like event properties before its size is
  /// measured, so the budget counts what is sent.
  void add(String message, {Map<String, Object>? properties}) {
    final timestamp = DateTime.now();
    if (message.isEmpty) {
      printIfDebug('[PostHog] addExceptionStep called with an empty message.');
      return;
    }

    final step = <String, Object?>{};
    properties?.forEach((key, value) {
      if (key == _messageKey || key == _timestampKey) {
        printIfDebug(
          '[PostHog] addExceptionStep: reserved key $key in properties is ignored.',
        );
      } else {
        step[key] = value;
      }
    });
    step[_messageKey] = message;
    step[_timestampKey] = _millisecondTimestamp(timestamp);

    final normalized = toJsonValue(PropertyNormalizer.normalize(step), _logger,
        dropNullMembers: true)! as Map<String, Object?>;
    final bytes = utf8.encode(jsonEncode(normalized)).length;
    if (bytes > _maxBytes) {
      printIfDebug(
        '[PostHog] Exception step dropped: $bytes bytes exceed maxBytes ($_maxBytes).',
      );
      return;
    }

    _entries.add((step: normalized, bytes: bytes));
    _totalBytes += bytes;
    while (_totalBytes > _maxBytes) {
      _totalBytes -= _entries.removeFirst().bytes;
    }
  }

  /// ISO 8601 in UTC with millisecond precision.
  static String _millisecondTimestamp(DateTime time) =>
      DateTime.fromMillisecondsSinceEpoch(
        time.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
}
