import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../feature_flag_result.dart';
import '../util/logging.dart';
import 'feature_flags_types.dart';
import 'feature_flags_utils.dart';

/// Parameters for a feature flag load request.
class _LoadParams {
  final String distinctId;
  final String? anonymousId;
  final Map<String, Object>? groups;
  final Map<String, Object>? personProperties;
  final Map<String, Map<String, Object>>? groupProperties;

  const _LoadParams({
    required this.distinctId,
    this.anonymousId,
    this.groups,
    this.personProperties,
    this.groupProperties,
  });
}

/// Manages feature flags fetched from PostHog's `/flags/?v=2` API.
///
/// Provides synchronous reads from an in-memory cache and handles
/// request coalescing, error merging, and quota limiting following
/// the patterns from the Android SDK's `PostHogRemoteConfig`.
class PostHogFeatureFlags {
  final String _apiKey;
  final String _host;
  final http.Client _httpClient;

  /// Cached flags (sync reads).
  Map<String, FeatureFlagDetail> _flags = {};
  bool _isLoaded = false;

  /// The request ID from the last successful flags response.
  String? requestId;

  /// The evaluation timestamp from the last successful flags response.
  int? evaluatedAt;

  /// Request coalescing state.
  Future<void>? _loadingFuture;
  Completer<void>? _pendingReload;
  _LoadParams? _pendingParams;

  /// Callback invoked when feature flags are updated.
  void Function(Map<String, PostHogFeatureFlagResult> flags)? onFeatureFlags;

  PostHogFeatureFlags({
    required String apiKey,
    required String host,
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _host = host.endsWith('/') ? host.substring(0, host.length - 1) : host,
        _httpClient = httpClient ?? http.Client();

  // ---------------------------------------------------------------------------
  // Public sync reads
  // ---------------------------------------------------------------------------

  /// Whether flags have been successfully loaded at least once.
  bool get isLoaded => _isLoaded;

  /// Returns a [PostHogFeatureFlagResult] for the given flag key,
  /// or `null` if the flag is not in the cache.
  PostHogFeatureFlagResult? getFeatureFlagResult(String key) {
    final detail = _flags[key];
    if (detail == null) return null;

    return PostHogFeatureFlagResult(
      key: detail.key,
      enabled: detail.enabled,
      variant: detail.variant,
      payload: detail.metadata?.payload,
    );
  }

  /// Returns `true` if the flag is enabled (exists and enabled).
  /// Returns `false` for unknown flags or disabled flags.
  bool isFeatureEnabled(String key) {
    return _flags[key]?.enabled ?? false;
  }

  /// Returns the flag value: variant string for multivariate flags,
  /// `true`/`false` for boolean flags, or `null` if not found.
  Object? getFeatureFlag(String key) {
    final detail = _flags[key];
    if (detail == null) return null;
    if (!detail.enabled) return false;
    return detail.variant ?? true;
  }

  /// Returns the payload associated with a feature flag, if any.
  Object? getFeatureFlagPayload(String key) {
    return _flags[key]?.metadata?.payload;
  }

  /// Returns all cached flags as a map of key → [PostHogFeatureFlagResult].
  Map<String, PostHogFeatureFlagResult> getAllFlags() {
    final result = <String, PostHogFeatureFlagResult>{};
    for (final entry in _flags.entries) {
      result[entry.key] = PostHogFeatureFlagResult(
        key: entry.key,
        enabled: entry.value.enabled,
        variant: entry.value.variant,
        payload: entry.value.metadata?.payload,
      );
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Async operations
  // ---------------------------------------------------------------------------

  /// Loads feature flags from the PostHog API.
  ///
  /// Uses request coalescing: if a request is already in-flight, the new
  /// request is queued and executed after the current one completes.
  /// This follows the Android SDK's `pendingFeatureFlagsReload` pattern.
  Future<void> loadFeatureFlags(
    String distinctId, {
    String? anonymousId,
    Map<String, Object>? groups,
    Map<String, Object>? personProperties,
    Map<String, Map<String, Object>>? groupProperties,
  }) async {
    final params = _LoadParams(
      distinctId: distinctId,
      anonymousId: anonymousId,
      groups: groups,
      personProperties: personProperties,
      groupProperties: groupProperties,
    );

    if (_loadingFuture != null) {
      // Request in-flight — queue this one
      _pendingReload?.complete();
      _pendingReload = Completer<void>();
      _pendingParams = params;
      return _pendingReload!.future;
    }

    _loadingFuture = _doLoadFeatureFlags(params);
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
      if (_pendingReload != null) {
        final pending = _pendingReload!;
        final pendingParams = _pendingParams!;
        _pendingReload = null;
        _pendingParams = null;
        loadFeatureFlags(
          pendingParams.distinctId,
          anonymousId: pendingParams.anonymousId,
          groups: pendingParams.groups,
          personProperties: pendingParams.personProperties,
          groupProperties: pendingParams.groupProperties,
        ).then((_) {
          if (!pending.isCompleted) {
            pending.complete();
          }
        }).catchError((e) {
          if (!pending.isCompleted) {
            pending.completeError(e);
          }
        });
      }
    }
  }

  Future<void> _doLoadFeatureFlags(_LoadParams params) async {
    final url = '$_host/flags/?v=2&config=true';

    final body = <String, Object?>{
      'token': _apiKey,
      'distinct_id': params.distinctId,
    };

    if (params.anonymousId != null) {
      body[r'$anon_distinct_id'] = params.anonymousId;
    }
    if (params.groups != null && params.groups!.isNotEmpty) {
      body['groups'] = params.groups;
    }
    if (params.personProperties != null &&
        params.personProperties!.isNotEmpty) {
      body['person_properties'] = params.personProperties;
    }
    if (params.groupProperties != null && params.groupProperties!.isNotEmpty) {
      body['group_properties'] = params.groupProperties;
    }

    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final result = parseFlagsResponse(response.body, response.statusCode);

      switch (result) {
        case GetFlagsSuccess(:final response):
          _applyResponse(response);
        case GetFlagsFailure(:final error):
          printIfDebug('[PostHog] Failed to load feature flags: $error');
      }
    } catch (e) {
      printIfDebug('[PostHog] Network error loading feature flags: $e');
    }
  }

  void _applyResponse(PostHogFlagsResponse response) {
    // Check quota limiting
    if (response.quotaLimited.contains('feature_flags')) {
      printIfDebug('[PostHog] Feature flags quota limited, skipping update');
      return;
    }

    if (response.errorsWhileComputingFlags) {
      // MERGE: only update non-failed flags, preserve existing cache for failed ones
      final successful = response.flags.entries
          .where((e) => e.value.failed != true);
      _flags = {..._flags, ...Map.fromEntries(successful)};
    } else {
      // REPLACE: full response, safe to overwrite
      _flags = Map.of(response.flags);
    }

    requestId = response.requestId;
    evaluatedAt = response.evaluatedAt;
    _isLoaded = true;

    // Notify callback
    onFeatureFlags?.call(getAllFlags());
  }

  /// Clears all cached flag state.
  void clear() {
    _flags = {};
    requestId = null;
    evaluatedAt = null;
    _isLoaded = false;
  }
}
