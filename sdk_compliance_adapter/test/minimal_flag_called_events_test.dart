import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  test(
    r'gated flag without experiment sends exactly the minimal allowlist',
    () async {
      final mockServer = await _MockPostHogServer.start({
        'flags': {
          'plain-flag': {
            'key': 'plain-flag',
            'enabled': true,
            'metadata': {'has_experiment': false},
          },
        },
        'featureFlags': {'plain-flag': true},
        'minimalFlagCalledEvents': true,
      });
      addTearDown(mockServer.close);

      final harness = await _AdapterHarness.start(mockServer);
      addTearDown(harness.close);

      final properties = await harness.captureFeatureFlagCalled('plain-flag');

      expect(
        properties.keys,
        unorderedEquals([
          'distinct_id',
          'token',
          r'$lib',
          r'$lib_version',
          r'$feature_flag',
          r'$feature_flag_response',
          r'$feature_flag_has_experiment',
        ]),
      );
      expect(properties['distinct_id'], 'test-user');
      expect(properties['token'], 'test-api-key');
      expect(properties[r'$feature_flag'], 'plain-flag');
      expect(properties[r'$feature_flag_response'], isTrue);
      expect(properties[r'$feature_flag_has_experiment'], isFalse);
    },
  );

  final fullEventCases = [
    (
      description: 'gated flag with an experiment sends the full event',
      response: <String, Object?>{
        'flags': {
          'experiment-flag': {
            'key': 'experiment-flag',
            'enabled': true,
            'variant': 'control',
            'metadata': {'has_experiment': true},
          },
        },
        'featureFlags': {'experiment-flag': 'control'},
        'minimalFlagCalledEvents': true,
      },
      key: 'experiment-flag',
      expectedHasExperiment: isTrue,
    ),
    (
      description: 'ungated flag without experiment sends the full event',
      response: <String, Object?>{
        'flags': {
          'plain-flag': {
            'key': 'plain-flag',
            'enabled': true,
            'metadata': {'has_experiment': false},
          },
        },
        'featureFlags': {'plain-flag': true},
      },
      key: 'plain-flag',
      expectedHasExperiment: isFalse,
    ),
    (
      description: 'gated flag with unreported has_experiment sends the '
          'full event',
      response: <String, Object?>{
        'featureFlags': {'plain-flag': true},
        'minimalFlagCalledEvents': true,
      },
      key: 'plain-flag',
      expectedHasExperiment: isNull,
    ),
    (
      description: 'gated flag with malformed has_experiment metadata sends '
          'the full event',
      response: <String, Object?>{
        'flags': {
          'plain-flag': {
            'key': 'plain-flag',
            'enabled': true,
            'metadata': {'has_experiment': 'not-a-bool'},
          },
        },
        'featureFlags': {'plain-flag': true},
        'minimalFlagCalledEvents': true,
      },
      key: 'plain-flag',
      expectedHasExperiment: isNull,
    ),
  ];

  for (final testCase in fullEventCases) {
    test(testCase.description, () async {
      final mockServer = await _MockPostHogServer.start(testCase.response);
      addTearDown(mockServer.close);

      final harness = await _AdapterHarness.start(mockServer);
      addTearDown(harness.close);

      final properties = await harness.captureFeatureFlagCalled(testCase.key);

      expect(properties[r'$feature_flag'], testCase.key);
      expect(properties, contains(r'$feature/' + testCase.key));
      expect(
        properties[r'$feature_flag_has_experiment'],
        testCase.expectedHasExperiment,
      );
    });
  }

  test('the gate tracks the latest flags response', () async {
    final mockServer = await _MockPostHogServer.start({
      'flags': {
        'plain-flag': {
          'key': 'plain-flag',
          'enabled': true,
          'metadata': {'has_experiment': false},
        },
      },
      'featureFlags': {'plain-flag': true},
      'minimalFlagCalledEvents': true,
    });
    addTearDown(mockServer.close);

    final harness = await _AdapterHarness.start(mockServer);
    addTearDown(harness.close);

    final gated = await harness.captureFeatureFlagCalled('plain-flag');
    expect(gated, isNot(contains(r'$feature/plain-flag')));

    mockServer.flagsResponse = {
      'featureFlags': {'plain-flag': true},
    };

    final ungated = await harness.captureFeatureFlagCalled('plain-flag');
    expect(ungated, contains(r'$feature/plain-flag'));
  });
}

/// Runs a [ComplianceAdapter] against a [_MockPostHogServer].
class _AdapterHarness {
  _AdapterHarness._(this._adapter, this._baseUrl, this._mockServer);

  final ComplianceAdapter _adapter;
  final String _baseUrl;
  final _MockPostHogServer _mockServer;

  static Future<_AdapterHarness> start(_MockPostHogServer mockServer) async {
    final adapter = ComplianceAdapter();
    final adapterServer = await adapter.start(port: 0);
    final baseUrl = 'http://127.0.0.1:${adapterServer.port}';
    await _postJson('$baseUrl/init', {
      'api_key': 'test-api-key',
      'host': mockServer.url,
      'flush_interval_ms': 60000,
    });
    return _AdapterHarness._(adapter, baseUrl, mockServer);
  }

  Future<void> close() => _adapter.close();

  /// Evaluates [key], flushes, and returns the properties of the
  /// `$feature_flag_called` event it produced.
  Future<Map<String, Object?>> captureFeatureFlagCalled(String key) async {
    final alreadyBatched = _mockServer.batchedEvents.length;
    final response = await _postJson('$_baseUrl/get_feature_flag', {
      'key': key,
      'distinct_id': 'test-user',
    });
    expect(response['success'], isTrue);

    await _postJson('$_baseUrl/flush', {});

    expect(_mockServer.batchedEvents, hasLength(alreadyBatched + 1));
    final event = _mockServer.batchedEvents.last;
    expect(event['event'], r'$feature_flag_called');
    return Map<String, Object?>.from(event['properties'] as Map);
  }
}

Future<Map<String, Object?>> _postJson(
  String url,
  Map<String, Object?> payload,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}

/// Serves `/flags/?v=2` with a swappable [flagsResponse] and records events
/// posted to `/batch`.
class _MockPostHogServer {
  _MockPostHogServer._(this._server, this.flagsResponse);

  final HttpServer _server;
  Map<String, Object?> flagsResponse;
  final List<Map<String, Object?>> batchedEvents = [];

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_MockPostHogServer> start(
    Map<String, Object?> flagsResponse,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mockServer = _MockPostHogServer._(server, flagsResponse);
    unawaited(mockServer._serve());
    return mockServer;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final body = await utf8.decoder.bind(request).join();
      if (request.method == 'POST' &&
          request.uri.path == '/flags/' &&
          request.uri.queryParameters['v'] == '2') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(flagsResponse));
        await request.response.close();
        continue;
      }

      if (request.method == 'POST' && request.uri.path == '/batch') {
        final decoded = jsonDecode(body) as Map;
        for (final event in decoded['batch'] as List) {
          batchedEvents.add(Map<String, Object?>.from(event as Map));
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 1}));
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}
