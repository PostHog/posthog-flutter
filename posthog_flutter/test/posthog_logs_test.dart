import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Posthog logs', () {
    late PosthogFlutterPlatformFake fake;

    setUp(() async {
      fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      await Posthog().close();
    });

    Future<void> setupWith(PostHogConfig config) async {
      await Posthog().setup(config);
    }

    group('Public capture API', () {
      test('captureLog with explicit level forwards body and level', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(
          body: 'checkout failed',
          level: PostHogLogSeverity.error,
        );

        expect(fake.capturedLogs, hasLength(1));
        expect(fake.capturedLogs.single.body, 'checkout failed');
        expect(fake.capturedLogs.single.level, PostHogLogSeverity.error);
      });

      test('logger helper delegates to captureLog', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().logger.info('ready', {'region': 'us'});

        expect(fake.capturedLogs, hasLength(1));
        final call = fake.capturedLogs.single;
        expect(call.body, 'ready');
        expect(call.level, PostHogLogSeverity.info);
        expect(call.attributes, {'region': 'us'});
      });

      test('missing level defaults to info', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(body: 'hello');

        expect(fake.capturedLogs.single.level, PostHogLogSeverity.info);
      });

      test('each logger level maps to its severity', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().logger.trace('a');
        await Posthog().logger.debug('b');
        await Posthog().logger.info('c');
        await Posthog().logger.warn('d');
        await Posthog().logger.error('e');
        await Posthog().logger.fatal('f');

        expect(
          fake.capturedLogs.map((c) => c.level).toList(),
          const [
            PostHogLogSeverity.trace,
            PostHogLogSeverity.debug,
            PostHogLogSeverity.info,
            PostHogLogSeverity.warn,
            PostHogLogSeverity.error,
            PostHogLogSeverity.fatal,
          ],
        );
      });
    });

    group('Trace correlation fields', () {
      test('forwards traceId, spanId, and traceFlags', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(
          body: 'request finished',
          traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
          spanId: '00f067aa0ba902b7',
          traceFlags: 1,
        );

        final call = fake.capturedLogs.single;
        expect(call.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
        expect(call.spanId, '00f067aa0ba902b7');
        expect(call.traceFlags, 1);
      });

      test('forwards an explicit traceFlags of 0 (sampled-false)', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(body: 'x', traceFlags: 0);

        expect(fake.capturedLogs.single.traceFlags, 0);
      });

      test('trace fields are null when not provided', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(body: 'x');

        final call = fake.capturedLogs.single;
        expect(call.traceId, isNull);
        expect(call.spanId, isNull);
        expect(call.traceFlags, isNull);
      });

      test('logger facade does not carry trace fields', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().logger.info('x');

        final call = fake.capturedLogs.single;
        expect(call.traceId, isNull);
        expect(call.spanId, isNull);
        expect(call.traceFlags, isNull);
      });
    });

    group('Capture-time gating', () {
      test('whitespace-only body is dropped', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(body: '   ');

        expect(fake.capturedLogs, isEmpty);
      });

      test('empty body is dropped', () async {
        await setupWith(PostHogConfig('test_token'));

        await Posthog().captureLog(body: '');

        expect(fake.capturedLogs, isEmpty);
      });
    });

    group('beforeSend hook', () {
      test('hook returning null drops the record', () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [(record) => null];
        await setupWith(config);

        await Posthog().captureLog(body: 'secret');

        expect(fake.capturedLogs, isEmpty);
      });

      test('hook can mutate body and attributes', () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [
          (record) {
            record.body = 'redacted';
            record.attributes = {'safe': true};
            return record;
          },
        ];
        await setupWith(config);

        await Posthog().captureLog(
          body: 'original',
          attributes: {'password': 'hunter2'},
        );

        expect(fake.capturedLogs.single.body, 'redacted');
        expect(fake.capturedLogs.single.attributes, {'safe': true});
      });

      test('hook blanking the body drops the record', () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [
          (record) {
            record.body = '   ';
            return record;
          },
        ];
        await setupWith(config);

        await Posthog().captureLog(body: 'original');

        expect(fake.capturedLogs, isEmpty);
      });

      test('throwing hook is contained and record continues', () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [
          (record) => throw Exception('boom'),
        ];
        await setupWith(config);

        await Posthog().captureLog(body: 'still sent');

        expect(fake.capturedLogs.single.body, 'still sent');
      });

      test('callbacks run left-to-right, feeding each output to the next',
          () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [
          (record) {
            record.body = '${record.body}-1';
            return record;
          },
          (record) {
            record.body = '${record.body}-2';
            return record;
          },
        ];
        await setupWith(config);

        await Posthog().captureLog(body: 'x');

        expect(fake.capturedLogs.single.body, 'x-1-2');
      });

      test('async hook is awaited', () async {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [
          (record) async {
            await Future<void>.delayed(Duration.zero);
            record.body = 'async';
            return record;
          },
        ];
        await setupWith(config);

        await Posthog().captureLog(body: 'x');

        expect(fake.capturedLogs.single.body, 'async');
      });
    });

    group('PostHogLogsConfig.toMap', () {
      test('omits unset identity fields and empty attributes', () {
        final config = PostHogConfig('test_token');

        expect(config.toMap()['logs'], isEmpty);
      });

      test('serializes set identity fields and attributes', () {
        final config = PostHogConfig('test_token');
        config.logs
          ..serviceName = 'checkout'
          ..serviceVersion = '1.2.3'
          ..environment = 'production'
          ..resourceAttributes = {'region': 'us'};

        expect(config.toMap()['logs'], {
          'serviceName': 'checkout',
          'serviceVersion': '1.2.3',
          'environment': 'production',
          'resourceAttributes': {'region': 'us'},
        });
      });

      test('serializes tuning knobs, sending durations as seconds', () {
        final config = PostHogConfig('test_token');
        config.logs
          ..flushInterval = const Duration(seconds: 15)
          ..flushAt = 5
          ..maxBatchSize = 25
          ..maxBufferSize = 200
          ..rateCapMaxLogs = 1000
          ..rateCapWindow = const Duration(seconds: 20);

        expect(config.toMap()['logs'], {
          'flushIntervalSeconds': 15,
          'flushAt': 5,
          'maxBatchSize': 25,
          'maxBufferSize': 200,
          'rateCapMaxLogs': 1000,
          'rateCapWindowSeconds': 20,
        });
      });

      test('floors sub-second flush/rate-cap durations at 1s (not 0)', () {
        final config = PostHogConfig('test_token');
        config.logs
          ..flushInterval = const Duration(milliseconds: 500)
          ..rateCapWindow = const Duration(milliseconds: 1);

        // Native windows are whole seconds; truncating to 0 would disable the
        // rate cap / trigger continuous flushing, so we floor at 1s.
        final logs = config.toMap()['logs'] as Map;
        expect(logs['flushIntervalSeconds'], 1);
        expect(logs['rateCapWindowSeconds'], 1);
      });

      test('omits the tuning knobs that were left unset', () {
        final config = PostHogConfig('test_token');
        config.logs
          ..flushAt = 5
          ..rateCapWindow = const Duration(seconds: 20);

        // Each field is guarded independently, so a partial config is the
        // realistic shape: only the two set keys should appear.
        expect(config.toMap()['logs'], {
          'flushAt': 5,
          'rateCapWindowSeconds': 20,
        });
      });

      test('beforeSend is never serialized', () {
        final config = PostHogConfig('test_token');
        config.logs.beforeSend = [(record) => record];

        expect(
          (config.toMap()['logs'] as Map).containsKey('beforeSend'),
          isFalse,
        );
      });
    });
  });
}
