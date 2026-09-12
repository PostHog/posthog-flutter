import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:posthog_flutter/posthog_flutter.dart';

import 'wire_observer.dart';

/// Runs inside a macOS Flutter application with the production plugin registered.
class ComplianceAdapter {
  final Posthog _sdk = Posthog();
  final WireObserver _wire = WireObserver();
  HttpServer? _server;
  bool _initialized = false;

  Future<void> start({required int port, required int proxyPort}) async {
    await _wire.start(proxyPort);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    await for (final request in _server!) {
      try {
        final result = await _route(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } catch (error, stack) {
        stderr.writeln('$error\n$stack');
        request.response.statusCode = error is UnsupportedError ? 501 : 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'success': false, 'error': '$error'}),
        );
      }
      await request.response.close();
    }
  }

  Future<Map<String, Object?>> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/health') {
      return {
        'sdk_name': 'posthog-flutter',
        'sdk_version': const String.fromEnvironment('SDK_VERSION'),
        'adapter_version': '2.0.0',
        'runtime': 'macos-flutter-method-channel',
        'delegate_version': const String.fromEnvironment('DELEGATE_VERSION'),
        'supports_parallel': false,
        'capabilities': ['capture_v0', 'encoding_gzip'],
      };
    }
    if (request.method == 'GET' && path == '/state') {
      throw UnsupportedError(
        'Flutter exposes no queue state or retry counters. '
        'Use /observations for passive wire records.',
      );
    }
    if (request.method == 'GET' && path == '/observations') {
      return {'requests': _wire.requests};
    }
    if (request.method != 'POST') throw UnsupportedError('Unknown route');
    final text = await utf8.decoder.bind(request).join();
    final body = text.isEmpty
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(text) as Map);
    if (path == '/init') {
      if (_initialized) {
        throw StateError('Each init requires a fresh Flutter process');
      }
      _wire.reset();
      _wire.target = Uri.parse(body['host'] as String);
      final config = PostHogConfig(body['api_key'] as String)
        ..host = _wire.url
        ..flushAt = (body['flush_at'] as int?) ?? 100
        ..flushInterval = Duration(
          milliseconds: (body['flush_interval_ms'] as int?) ?? 1000,
        )
        ..captureApplicationLifecycleEvents = false
        ..preloadFeatureFlags = false;
      await _sdk.setup(config);
      _initialized = true;
      return {'success': true};
    }
    if (!_initialized) throw StateError('SDK not initialized');
    switch (path) {
      case '/capture':
        if (body['timestamp'] != null) {
          throw UnsupportedError('Flutter capture has no timestamp override');
        }
        await _identify(body['distinct_id'] as String);
        final event = body['event'] as String;
        _wire.expectCapture(event);
        await _sdk.capture(
          eventName: event,
          properties: _properties(body['properties']),
        );
        return {'success': true, 'uuid': null};
      case '/get_feature_flag':
        await _identify(body['distinct_id'] as String);
        await _sdk.resetPersonPropertiesForFlags(reloadFeatureFlags: false);
        await _sdk.resetGroupPropertiesForFlags(reloadFeatureFlags: false);
        await _sdk.setPersonPropertiesForFlags(
          _properties(body['person_properties']),
          reloadFeatureFlags: false,
        );
        final groupProperties = (body['group_properties'] as Map?) ?? {};
        for (final entry in ((body['groups'] as Map?) ?? {}).entries) {
          await _sdk.group(
            groupType: entry.key as String,
            groupKey: entry.value.toString(),
          );
          await _sdk.setGroupPropertiesForFlags(
            entry.key as String,
            _properties(groupProperties[entry.key]),
            reloadFeatureFlags: false,
          );
        }
        if (body['force_remote'] != false) await _sdk.reloadFeatureFlags();
        final value = await _sdk.getFeatureFlag(body['key'] as String);
        return {'success': true, 'value': value};
      case '/flush':
        await _sdk.flush();
        await _wire.waitForObservedCaptures();
        return {
          'success': true,
          'events_flushed': null,
          'observation': 'submitted captures reached terminal HTTP responses; '
              'not a native queue-drain guarantee',
        };
      default:
        throw UnsupportedError('Unknown route');
    }
  }

  Future<void> _identify(String distinctId) async {
    if (await _sdk.getDistinctId() != distinctId) {
      await _sdk.identify(userId: distinctId);
    }
  }
}

Map<String, Object> _properties(Object? value) => {
      for (final entry in ((value as Map?) ?? {}).entries)
        if (entry.value != null) entry.key as String: entry.value as Object,
    };
