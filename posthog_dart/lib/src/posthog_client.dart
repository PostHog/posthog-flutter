import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'http.dart';
import 'posthog_core.dart';
import 'version.dart';

/// Ready-to-use PostHog client for Dart applications.
///
/// Uses `package:http` for network requests with gzip compression.
/// Suitable for all platforms (mobile, desktop, server, web).
///
/// ```dart
/// final posthog = PostHog('phc_your_api_key');
/// posthog.capture('event_name', properties: {'key': 'value'});
/// ```
///
/// For Flutter apps with persistent storage, use [FileStorage] from
/// `package:posthog_dart/src/file_storage.dart`:
///
/// ```dart
/// final dir = await getApplicationSupportDirectory();
/// final posthog = PostHog(
///   'phc_your_api_key',
///   storage: FileStorage(dir.path),
/// );
/// ```
class PostHog extends PostHogCore {
  final http.Client _httpClient;
  final bool _ownClient;

  /// Creates a PostHog client.
  ///
  /// - [apiKey]: Your PostHog project API key.
  /// - [options]: Configuration options.
  /// - [storage]: Storage implementation. Defaults to [InMemoryStorage].
  /// - [httpClient]: Optional custom [http.Client]. If not provided, a default
  ///   client is created and closed on [shutdown].
  PostHog(
    super.apiKey, {
    super.options,
    super.storage,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownClient = httpClient == null;

  @override
  Future<PostHogFetchResponse> fetch(
      String url, PostHogFetchOptions options) async {
    final uri = Uri.parse(url);
    final http.Response response;

    switch (options.method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: options.headers);
      case 'POST':
        final body = options.body;
        if (body != null) {
          final compressed = gzip.encode(utf8.encode(body));
          response = await _httpClient.post(
            uri,
            headers: {
              ...options.headers,
              'Content-Encoding': 'gzip',
            },
            body: compressed,
          );
        } else {
          response = await _httpClient.post(uri, headers: options.headers);
        }
      default:
        throw ArgumentError('Unsupported HTTP method: ${options.method}');
    }

    return PostHogFetchResponse(
      status: response.statusCode,
      body: response.body,
    );
  }

  @override
  String getLibraryId() => 'posthog-dart';

  @override
  String getLibraryVersion() => sdkVersion;

  @override
  String? getCustomUserAgent() => 'posthog-dart/$sdkVersion';

  /// Shuts down the client, flushing pending events and closing the HTTP client.
  @override
  Future<void> shutdown({int timeoutMs = 30000}) async {
    await super.shutdown(timeoutMs: timeoutMs);
    if (_ownClient) {
      _httpClient.close();
    }
  }
}
