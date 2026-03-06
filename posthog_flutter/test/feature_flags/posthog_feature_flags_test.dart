import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/feature_flags/feature_flags_types.dart';
import 'package:posthog_flutter/src/feature_flags/feature_flags_utils.dart';
import 'package:posthog_flutter/src/feature_flags/posthog_feature_flags.dart';

/// Helper to build a standard v2 flags response JSON.
String _buildFlagsResponse({
  Map<String, dynamic>? flags,
  bool errorsWhileComputingFlags = false,
  List<String>? quotaLimited,
  String? requestId,
  int? evaluatedAt,
}) {
  return jsonEncode({
    'flags': flags ?? {},
    'errorsWhileComputingFlags': errorsWhileComputingFlags,
    if (quotaLimited != null) 'quotaLimited': quotaLimited,
    if (requestId != null) 'requestId': requestId,
    if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
  });
}

/// Helper to build a flag detail JSON object.
Map<String, dynamic> _flagDetail({
  required bool enabled,
  String? variant,
  bool? failed,
  Map<String, dynamic>? metadata,
  Map<String, dynamic>? reason,
}) {
  return {
    'enabled': enabled,
    if (variant != null) 'variant': variant,
    if (failed != null) 'failed': failed,
    if (metadata != null) 'metadata': metadata,
    if (reason != null) 'reason': reason,
  };
}

void main() {
  group('parseFlagsResponse', () {
    test('parses valid v2 flags response', () {
      final body = _buildFlagsResponse(
        flags: {
          'bool-flag': _flagDetail(enabled: true),
          'disabled-flag': _flagDetail(enabled: false),
          'variant-flag': _flagDetail(enabled: true, variant: 'control'),
        },
        requestId: 'req-123',
        evaluatedAt: 1700000000,
      );

      final result = parseFlagsResponse(body, 200);
      expect(result, isA<GetFlagsSuccess>());

      final response = (result as GetFlagsSuccess).response;
      expect(response.flags.length, 3);
      expect(response.flags['bool-flag']!.enabled, true);
      expect(response.flags['bool-flag']!.variant, isNull);
      expect(response.flags['disabled-flag']!.enabled, false);
      expect(response.flags['variant-flag']!.variant, 'control');
      expect(response.requestId, 'req-123');
      expect(response.evaluatedAt, 1700000000);
    });

    test('parses errorsWhileComputingFlags', () {
      final body = _buildFlagsResponse(
        flags: {
          'ok-flag': _flagDetail(enabled: true),
          'failed-flag': _flagDetail(enabled: false, failed: true),
        },
        errorsWhileComputingFlags: true,
      );

      final result = parseFlagsResponse(body, 200);
      final response = (result as GetFlagsSuccess).response;
      expect(response.errorsWhileComputingFlags, true);
      expect(response.flags['failed-flag']!.failed, true);
    });

    test('parses quotaLimited', () {
      final body = _buildFlagsResponse(
        quotaLimited: ['feature_flags'],
      );

      final result = parseFlagsResponse(body, 200);
      final response = (result as GetFlagsSuccess).response;
      expect(response.quotaLimited, ['feature_flags']);
    });

    test('returns failure for HTTP error', () {
      final result = parseFlagsResponse('Internal Server Error', 500);
      expect(result, isA<GetFlagsFailure>());
      final error = (result as GetFlagsFailure).error;
      expect(error.type, FeatureFlagRequestErrorType.httpError);
      expect(error.statusCode, 500);
    });

    test('returns failure for invalid JSON', () {
      final result = parseFlagsResponse('not json', 200);
      expect(result, isA<GetFlagsFailure>());
      final error = (result as GetFlagsFailure).error;
      expect(error.type, FeatureFlagRequestErrorType.parseError);
    });

    test('parses metadata with payload', () {
      final body = _buildFlagsResponse(
        flags: {
          'flag-with-payload': _flagDetail(
            enabled: true,
            metadata: {
              'id': 42,
              'version': 3,
              'description': 'A test flag',
              'payload': '{"key":"value"}',
            },
          ),
        },
      );

      final result = parseFlagsResponse(body, 200);
      final response = (result as GetFlagsSuccess).response;
      final flag = response.flags['flag-with-payload']!;
      expect(flag.metadata!.id, 42);
      expect(flag.metadata!.version, 3);
      expect(flag.metadata!.description, 'A test flag');
      // Payload should be parsed from JSON string
      expect(flag.metadata!.payload, {'key': 'value'});
    });

    test('parses evaluation reason', () {
      final body = _buildFlagsResponse(
        flags: {
          'flag-with-reason': _flagDetail(
            enabled: true,
            reason: {
              'code': 'condition_match',
              'condition_index': 2,
              'description': 'Matched condition 2',
            },
          ),
        },
      );

      final result = parseFlagsResponse(body, 200);
      final response = (result as GetFlagsSuccess).response;
      final flag = response.flags['flag-with-reason']!;
      expect(flag.reason!.code, 'condition_match');
      expect(flag.reason!.conditionIndex, 2);
      expect(flag.reason!.description, 'Matched condition 2');
    });

    test('handles empty flags object', () {
      final body = _buildFlagsResponse(flags: {});

      final result = parseFlagsResponse(body, 200);
      final response = (result as GetFlagsSuccess).response;
      expect(response.flags, isEmpty);
    });
  });

  group('PostHogFlagsResponse derived getters', () {
    test('featureFlags returns values map', () {
      final response = PostHogFlagsResponse(
        flags: {
          'bool-flag': const FeatureFlagDetail(key: 'bool-flag', enabled: true),
          'variant-flag': const FeatureFlagDetail(
              key: 'variant-flag', enabled: true, variant: 'test'),
          'disabled-flag':
              const FeatureFlagDetail(key: 'disabled-flag', enabled: false),
        },
      );

      final featureFlags = response.featureFlags;
      expect(featureFlags['bool-flag'], true);
      expect(featureFlags['variant-flag'], 'test');
      expect(featureFlags.containsKey('disabled-flag'), false);
    });

    test('featureFlagPayloads returns payloads', () {
      final response = PostHogFlagsResponse(
        flags: {
          'flag-with-payload': const FeatureFlagDetail(
            key: 'flag-with-payload',
            enabled: true,
            metadata: FeatureFlagMetadata(payload: 'test-payload'),
          ),
          'flag-no-payload': const FeatureFlagDetail(
            key: 'flag-no-payload',
            enabled: true,
          ),
        },
      );

      final payloads = response.featureFlagPayloads;
      expect(payloads['flag-with-payload'], 'test-payload');
      expect(payloads.containsKey('flag-no-payload'), false);
    });
  });

  group('PostHogFeatureFlags sync reads', () {
    late PostHogFeatureFlags featureFlags;

    setUp(() {
      final mockClient = MockClient((request) async {
        return http.Response(
          _buildFlagsResponse(
            flags: {
              'bool-flag': _flagDetail(enabled: true),
              'disabled-flag': _flagDetail(enabled: false),
              'variant-flag':
                  _flagDetail(enabled: true, variant: 'test-variant'),
              'payload-flag': _flagDetail(
                enabled: true,
                metadata: {
                  'id': 1,
                  'version': 1,
                  'payload': '{"setting":true}',
                },
              ),
            },
            requestId: 'req-1',
            evaluatedAt: 1700000000,
          ),
          200,
        );
      });

      featureFlags = PostHogFeatureFlags(
        apiKey: 'test-api-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );
    });

    test('isLoaded is false before loading', () {
      expect(featureFlags.isLoaded, false);
    });

    test('isLoaded is true after loading', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isLoaded, true);
    });

    test('isFeatureEnabled returns correct values', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('bool-flag'), true);
      expect(featureFlags.isFeatureEnabled('disabled-flag'), false);
      expect(featureFlags.isFeatureEnabled('variant-flag'), true);
    });

    test('isFeatureEnabled returns false for unknown flags', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('unknown-flag'), false);
    });

    test('getFeatureFlag returns correct values', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.getFeatureFlag('bool-flag'), true);
      expect(featureFlags.getFeatureFlag('disabled-flag'), false);
      expect(featureFlags.getFeatureFlag('variant-flag'), 'test-variant');
    });

    test('getFeatureFlag returns null for unknown flags', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.getFeatureFlag('unknown-flag'), isNull);
    });

    test('getFeatureFlagResult returns PostHogFeatureFlagResult', () async {
      await featureFlags.loadFeatureFlags('user-1');

      final result = featureFlags.getFeatureFlagResult('variant-flag');
      expect(result, isNotNull);
      expect(result!.key, 'variant-flag');
      expect(result.enabled, true);
      expect(result.variant, 'test-variant');
    });

    test('getFeatureFlagResult returns null for unknown flags', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.getFeatureFlagResult('unknown-flag'), isNull);
    });

    test('getFeatureFlagPayload returns parsed payload', () async {
      await featureFlags.loadFeatureFlags('user-1');
      final payload = featureFlags.getFeatureFlagPayload('payload-flag');
      expect(payload, {'setting': true});
    });

    test('getAllFlags returns all flags as PostHogFeatureFlagResult', () async {
      await featureFlags.loadFeatureFlags('user-1');
      final allFlags = featureFlags.getAllFlags();
      expect(allFlags.length, 4);
      expect(allFlags['bool-flag'], isA<PostHogFeatureFlagResult>());
      expect(allFlags['bool-flag']!.enabled, true);
    });

    test('clear resets all state', () async {
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isLoaded, true);

      featureFlags.clear();
      expect(featureFlags.isLoaded, false);
      expect(featureFlags.isFeatureEnabled('bool-flag'), false);
      expect(featureFlags.getAllFlags(), isEmpty);
      expect(featureFlags.requestId, isNull);
      expect(featureFlags.evaluatedAt, isNull);
    });
  });

  group('PostHogFeatureFlags HTTP request', () {
    test('sends correct request body', () async {
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          _buildFlagsResponse(flags: {}),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'phc_test123',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags(
        'user-distinct-id',
        anonymousId: 'anon-123',
        groups: {'company': 'posthog'},
      );

      expect(capturedBody!['token'], 'phc_test123');
      expect(capturedBody!['distinct_id'], 'user-distinct-id');
      expect(capturedBody![r'$anon_distinct_id'], 'anon-123');
      expect(capturedBody!['groups'], {'company': 'posthog'});
    });

    test('sends request to correct URL', () async {
      Uri? capturedUri;

      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          _buildFlagsResponse(flags: {}),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags('user-1');

      expect(capturedUri.toString(),
          'https://us.i.posthog.com/flags/?v=2&config=true');
    });

    test('omits optional fields when not provided', () async {
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          _buildFlagsResponse(flags: {}),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags('user-1');

      expect(capturedBody!.containsKey(r'$anon_distinct_id'), false);
      expect(capturedBody!.containsKey('groups'), false);
    });
  });

  group('PostHogFeatureFlags request coalescing', () {
    test('concurrent calls result in at most 2 requests', () async {
      var requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        // Simulate network delay
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          _buildFlagsResponse(flags: {
            'flag': _flagDetail(enabled: true),
          }),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      // Fire multiple concurrent loads
      final futures = [
        featureFlags.loadFeatureFlags('user-1'),
        featureFlags.loadFeatureFlags('user-2'),
        featureFlags.loadFeatureFlags('user-3'),
      ];

      await Future.wait(futures);

      // Should be at most 2: one in-flight + one queued
      expect(requestCount, lessThanOrEqualTo(2));
    });
  });

  group('PostHogFeatureFlags error merging', () {
    test('merges only non-failed flags when errorsWhileComputingFlags is true',
        () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          // First call: full success
          return http.Response(
            _buildFlagsResponse(flags: {
              'flag-a': _flagDetail(enabled: true),
              'flag-b': _flagDetail(enabled: true, variant: 'original'),
            }),
            200,
          );
        } else {
          // Second call: partial failure
          return http.Response(
            _buildFlagsResponse(
              flags: {
                'flag-a': _flagDetail(enabled: false),
                'flag-b': _flagDetail(enabled: false, failed: true),
              },
              errorsWhileComputingFlags: true,
            ),
            200,
          );
        }
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      // First load — full cache
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('flag-a'), true);
      expect(featureFlags.getFeatureFlag('flag-b'), 'original');

      // Second load — partial errors
      await featureFlags.loadFeatureFlags('user-1');
      // flag-a should be updated (not failed)
      expect(featureFlags.isFeatureEnabled('flag-a'), false);
      // flag-b should preserve original (it failed)
      expect(featureFlags.getFeatureFlag('flag-b'), 'original');
    });

    test('replaces all flags when errorsWhileComputingFlags is false',
        () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            _buildFlagsResponse(flags: {
              'flag-a': _flagDetail(enabled: true),
              'flag-b': _flagDetail(enabled: true),
            }),
            200,
          );
        } else {
          return http.Response(
            _buildFlagsResponse(flags: {
              'flag-a': _flagDetail(enabled: false),
              // flag-b deliberately omitted
            }),
            200,
          );
        }
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.getAllFlags().length, 2);

      await featureFlags.loadFeatureFlags('user-1');
      // Full replace: flag-b should be gone
      expect(featureFlags.getAllFlags().length, 1);
      expect(featureFlags.isFeatureEnabled('flag-a'), false);
      expect(featureFlags.getFeatureFlag('flag-b'), isNull);
    });
  });

  group('PostHogFeatureFlags quota limiting', () {
    test('skips update when feature_flags is quota limited', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            _buildFlagsResponse(flags: {
              'flag': _flagDetail(enabled: true),
            }),
            200,
          );
        } else {
          return http.Response(
            _buildFlagsResponse(
              flags: {
                'flag': _flagDetail(enabled: false),
              },
              quotaLimited: ['feature_flags'],
            ),
            200,
          );
        }
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('flag'), true);

      // Second load — quota limited, should not update
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('flag'), true);
    });
  });

  group('PostHogFeatureFlags callback', () {
    test('onFeatureFlags fires with flags map after successful load', () async {
      Map<String, PostHogFeatureFlagResult>? receivedFlags;

      final mockClient = MockClient((request) async {
        return http.Response(
          _buildFlagsResponse(flags: {
            'test-flag': _flagDetail(enabled: true, variant: 'beta'),
          }),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      featureFlags.onFeatureFlags = (flags) {
        receivedFlags = flags;
      };

      await featureFlags.loadFeatureFlags('user-1');

      expect(receivedFlags, isNotNull);
      expect(receivedFlags!['test-flag']!.enabled, true);
      expect(receivedFlags!['test-flag']!.variant, 'beta');
    });

    test('onFeatureFlags does not fire on HTTP error', () async {
      var callbackCalled = false;

      final mockClient = MockClient((request) async {
        return http.Response('error', 500);
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      featureFlags.onFeatureFlags = (_) {
        callbackCalled = true;
      };

      await featureFlags.loadFeatureFlags('user-1');
      expect(callbackCalled, false);
    });

    test('onFeatureFlags does not fire when quota limited', () async {
      var callbackCount = 0;

      var isQuotaLimited = false;
      final mockClient = MockClient((request) async {
        return http.Response(
          _buildFlagsResponse(
            flags: {'flag': _flagDetail(enabled: true)},
            quotaLimited: isQuotaLimited ? ['feature_flags'] : [],
          ),
          200,
        );
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      featureFlags.onFeatureFlags = (_) {
        callbackCount++;
      };

      await featureFlags.loadFeatureFlags('user-1');
      expect(callbackCount, 1);

      isQuotaLimited = true;
      await featureFlags.loadFeatureFlags('user-1');
      // Should still be 1 — callback not fired for quota limited
      expect(callbackCount, 1);
    });
  });

  group('PostHogFeatureFlags error handling', () {
    test('handles network error gracefully', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      // Should not throw
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isLoaded, false);
    });

    test('preserves cache on error', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(
            _buildFlagsResponse(flags: {
              'flag': _flagDetail(enabled: true),
            }),
            200,
          );
        }
        throw Exception('Network error');
      });

      final featureFlags = PostHogFeatureFlags(
        apiKey: 'test-key',
        host: 'https://us.i.posthog.com',
        httpClient: mockClient,
      );

      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('flag'), true);

      // Second call fails — cache should be preserved
      await featureFlags.loadFeatureFlags('user-1');
      expect(featureFlags.isFeatureEnabled('flag'), true);
    });
  });
}
