import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'event_emitter.dart';
import 'feature_flag_utils.dart';
import 'storage.dart';
import 'types.dart';
import 'utils/utils.dart';
import 'uuid.dart';

/// HTTP error during PostHog fetch.
class PostHogFetchHttpError implements Exception {
  final int status;
  final String responseBody;
  final int reqByteLength;

  PostHogFetchHttpError(this.status, this.responseBody, this.reqByteLength);

  @override
  String toString() =>
      'PostHogFetchHttpError: status=$status, reqByteLength=$reqByteLength';
}

/// Network error during PostHog fetch.
class PostHogFetchNetworkError implements Exception {
  final Object? cause;
  PostHogFetchNetworkError(this.cause);

  @override
  String toString() => 'PostHogFetchNetworkError: $cause';
}

bool _isPostHogFetchError(Object err) =>
    err is PostHogFetchHttpError || err is PostHogFetchNetworkError;

/// Base stateless PostHog client with queue management and HTTP operations.
///
/// Subclasses must implement [fetch], [getLibraryId], [getLibraryVersion],
/// and [getCustomUserAgent].
abstract class PostHogCoreStateless {
  // options
  final String apiKey;
  final String host;
  @protected
  final int flushAt;
  @protected
  final bool preloadFeatureFlags;
  int _maxBatchSize;
  final int _maxQueueSize;
  final int _flushInterval;
  final int _requestTimeout;
  final int _featureFlagsRequestTimeoutMs;
  final int _remoteConfigRequestTimeoutMs;
  final bool _disableGeoip;
  final List<String>? _evaluationContexts;
  @protected
  bool disabled;

  final bool _defaultOptIn;
  final int _fetchRetryCount;
  final int _fetchRetryDelay;

  // internal
  @protected
  final SimpleEventEmitter events = SimpleEventEmitter();
  Timer? _flushTimer;
  Future<void>? _flushFuture;
  @protected
  bool isInitialized = false;
  @protected
  late final PostHogLogger logger;
  void Function()? _removeDebugCallback;

  // Storage
  @protected
  final PostHogStorage storage;

  // Abstract methods — for subclass implementors only.
  @protected
  Future<PostHogFetchResponse> fetch(String url, PostHogFetchOptions options);
  @protected
  String getLibraryId();
  @protected
  String getLibraryVersion();
  @protected
  String? getCustomUserAgent();

  PostHogCoreStateless(
    this.apiKey, {
    PostHogCoreOptions options = const PostHogCoreOptions(),
    PostHogStorage? storage,
  })  : storage = storage ?? InMemoryStorage(),
        host = removeTrailingSlash(options.host),
        flushAt = options.flushAt < 1 ? 1 : options.flushAt,
        _maxBatchSize = options.maxBatchSize > options.flushAt
            ? options.maxBatchSize
            : options.flushAt,
        _maxQueueSize = options.maxQueueSize > options.flushAt
            ? options.maxQueueSize
            : options.flushAt,
        _flushInterval = options.flushInterval,
        preloadFeatureFlags = options.preloadFeatureFlags,
        _defaultOptIn = options.defaultOptIn,
        _fetchRetryCount = options.fetchRetryCount,
        _fetchRetryDelay = options.fetchRetryDelay,
        _requestTimeout = options.requestTimeout,
        _featureFlagsRequestTimeoutMs =
            options.featureFlagsRequestTimeoutMs ?? 3000,
        _remoteConfigRequestTimeoutMs = options.remoteConfigRequestTimeoutMs,
        _disableGeoip = options.disableGeoip ?? true,
        disabled = options.disabled,
        _evaluationContexts = options.evaluationContexts {
    assertNotEmpty(apiKey, "You must pass your PostHog project's api key.");
    logger = PostHogLogger('[PostHog]', _logMsgIfDebug);
    isInitialized = true;
  }

  void _logMsgIfDebug(void Function() fn) {
    if (isDebug) {
      fn();
    }
  }

  /// Wraps a function call, skipping if disabled or waiting for init.
  @protected
  void wrap(void Function() fn) {
    if (disabled) {
      logger.warn('The client is disabled');
      return;
    }
    if (isInitialized) {
      fn();
    }
  }

  /// Gets common event properties.
  @protected
  Map<String, Object?> getCommonEventProperties() {
    return {
      r'$lib': getLibraryId(),
      r'$lib_version': getLibraryVersion(),
    };
  }

  // Persisted property access via storage
  @protected
  T? getPersistedProperty<T>(PostHogPersistedProperty key) {
    return storage.getProperty<T>(key);
  }

  @protected
  void setPersistedProperty<T>(PostHogPersistedProperty key, T? value) {
    storage.setProperty<T>(key, value);
  }

  /// Whether the user has opted out.
  bool get optedOut =>
      getPersistedProperty<bool>(PostHogPersistedProperty.optedOut) ??
      !_defaultOptIn;

  /// Opt in to tracking.
  void optIn() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.optedOut, false);
    });
  }

  /// Opt out of tracking.
  void optOut() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.optedOut, true);
    });
  }

  /// Register a listener for an event.
  void Function() on(String event, Function listener) {
    return events.on(event, listener);
  }

  /// Enables or disables debug mode.
  void debug([bool enabled = true]) {
    _removeDebugCallback?.call();
    _removeDebugCallback = null;

    if (enabled) {
      final remove = on('*', (event, payload) => logger.info(event, payload));
      _removeDebugCallback = remove;
    }
  }

  bool get isDebug => _removeDebugCallback != null;
  bool get isDisabled => disabled;

  Map<String, Object?> _buildPayload({
    required String distinctId,
    required String event,
    Map<String, Object?>? properties,
  }) {
    return {
      'distinct_id': distinctId,
      'event': event,
      'properties': {
        ...(properties ?? {}),
        ...getCommonEventProperties(),
      },
    };
  }

  ///

  @protected
  void identifyStateless(
    String distinctId, {
    Map<String, Object?>? properties,
    PostHogCaptureOptions? options,
  }) {
    wrap(() {
      final payload = _buildPayload(
        distinctId: distinctId,
        event: r'$identify',
        properties: properties,
      );
      enqueue('identify', payload, options: options);
    });
  }

  @protected
  void captureStateless(
    String distinctId,
    String event, {
    Map<String, Object?>? properties,
    PostHogCaptureOptions? options,
  }) {
    wrap(() {
      final payload = _buildPayload(
        distinctId: distinctId,
        event: event,
        properties: properties,
      );
      enqueue('capture', payload, options: options);
    });
  }

  @protected
  void aliasStateless(
    String alias,
    String distinctId, {
    Map<String, Object?>? properties,
    PostHogCaptureOptions? options,
  }) {
    wrap(() {
      final payload = _buildPayload(
        distinctId: distinctId,
        event: r'$create_alias',
        properties: {
          ...(properties ?? {}),
          'distinct_id': distinctId,
          'alias': alias,
        },
      );
      enqueue('alias', payload, options: options);
    });
  }

  @protected
  void groupIdentifyStateless(
    String groupType,
    Object groupKey, {
    Map<String, Object?>? groupProperties,
    PostHogCaptureOptions? options,
    String? distinctId,
    Map<String, Object?>? eventProperties,
  }) {
    wrap(() {
      final payload = _buildPayload(
        distinctId: distinctId ?? '\$${groupType}_$groupKey',
        event: r'$groupidentify',
        properties: {
          r'$group_type': groupType,
          r'$group_key': groupKey,
          r'$group_set': groupProperties ?? {},
          ...(eventProperties ?? {}),
        },
      );
      enqueue('capture', payload, options: options);
    });
  }

  ///

  @protected
  Future<PostHogRemoteConfig?> getRemoteConfig() async {
    var configHost = host;
    if (configHost == 'https://us.i.posthog.com') {
      configHost = 'https://us-assets.i.posthog.com';
    } else if (configHost == 'https://eu.i.posthog.com') {
      configHost = 'https://eu-assets.i.posthog.com';
    }

    final url = '$configHost/array/$apiKey/config';
    try {
      final response = await _fetchWithRetry(
        url,
        PostHogFetchOptions(
          method: 'GET',
          headers: {..._getCustomHeaders(), 'Content-Type': 'application/json'},
        ),
        retryCount: 0,
        timeoutMs: _remoteConfigRequestTimeoutMs,
      );
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return PostHogRemoteConfig.fromJson(json);
    } catch (e) {
      logger.error('Remote config could not be loaded', e);
      events.emit('error', e);
      return null;
    }
  }

  ///

  @protected
  Future<GetFlagsResult> getFlags(
    String distinctId, {
    Map<String, Object> groups = const {},
    Map<String, String> personProperties = const {},
    Map<String, Map<String, String>> groupProperties = const {},
    Map<String, Object?> extraPayload = const {},
  }) async {
    final url = '$host/flags/?v=2&config=true';

    final requestData = <String, Object?>{
      'token': apiKey,
      'distinct_id': distinctId,
      'groups': groups,
      'person_properties': personProperties,
      'group_properties': groupProperties,
      ...extraPayload,
    };

    if (_evaluationContexts != null && _evaluationContexts.isNotEmpty) {
      requestData['evaluation_contexts'] = _evaluationContexts;
    }

    logger.info('Flags URL', url);

    try {
      final response = await _fetchWithRetry(
        url,
        PostHogFetchOptions(
          method: 'POST',
          headers: {..._getCustomHeaders(), 'Content-Type': 'application/json'},
          body: jsonEncode(requestData),
        ),
        retryCount: 0,
        timeoutMs: _featureFlagsRequestTimeoutMs,
      );
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return GetFlagsSuccess(parseFlagsResponse(json));
    } catch (e) {
      events.emit('error', e);
      return GetFlagsFailure(_categorizeRequestError(e));
    }
  }

  FeatureFlagRequestError _categorizeRequestError(Object error) {
    if (error is PostHogFetchHttpError) {
      return FeatureFlagRequestError(
          type: FeatureFlagRequestErrorType.apiError, statusCode: error.status);
    }
    if (error is PostHogFetchNetworkError) {
      if (error.cause is TimeoutException) {
        return const FeatureFlagRequestError(
            type: FeatureFlagRequestErrorType.timeout);
      }
      return const FeatureFlagRequestError(
          type: FeatureFlagRequestErrorType.connectionError);
    }
    return const FeatureFlagRequestError(
        type: FeatureFlagRequestErrorType.unknownError);
  }

  @protected
  Future<FeatureFlagValue?> getFeatureFlagStateless(
    String key,
    String distinctId, {
    Map<String, String> groups = const {},
    Map<String, String> personProperties = const {},
    Map<String, Map<String, String>> groupProperties = const {},
    bool? disableGeoip,
  }) async {
    final extraPayload = <String, Object?>{};
    if (disableGeoip ?? _disableGeoip) {
      extraPayload['geoip_disable'] = true;
    }
    extraPayload['flag_keys_to_evaluate'] = [key];

    final result = await getFlags(
      distinctId,
      groups: groups,
      personProperties: personProperties,
      groupProperties: groupProperties,
      extraPayload: extraPayload,
    );

    if (result is GetFlagsFailure) return null;

    final response = (result as GetFlagsSuccess).response;
    final flagDetail = response.flags[key];
    var value = getFeatureFlagValue(flagDetail);
    return value ?? false;
  }

  ///

  Map<String, Object?>? _props;

  @protected
  Map<String, Object?> get props {
    _props ??= getPersistedProperty<Map<String, Object?>>(
            PostHogPersistedProperty.props) ??
        {};
    return _props ?? {};
  }

  @protected
  set props(Map<String, Object?>? val) {
    _props = val;
  }

  void register(Map<String, Object?> properties) {
    wrap(() {
      _props = {...props, ...properties};
      setPersistedProperty(PostHogPersistedProperty.props, _props);
    });
  }

  void unregister(String property) {
    wrap(() {
      props.remove(property);
      setPersistedProperty(PostHogPersistedProperty.props, props);
    });
  }

  ///

  /// Hook for subclasses to transform or filter a message before queueing.
  @protected
  Map<String, Object?>? processBeforeEnqueue(Map<String, Object?> message) {
    return message;
  }

  @protected
  void enqueue(String type, Map<String, Object?> message,
      {PostHogCaptureOptions? options}) {
    wrap(() {
      if (optedOut) {
        events.emit(type,
            'Library is disabled. Not sending event. To re-enable, call posthog.optIn()');
        return;
      }

      Map<String, Object?>? prepared = _prepareMessage(type, message, options);
      prepared = processBeforeEnqueue(prepared);
      if (prepared == null) return;

      final queue =
          getPersistedProperty<List<Object?>>(PostHogPersistedProperty.queue) ??
              [];

      final mutableQueue = List<Object?>.from(queue);
      if (mutableQueue.length >= _maxQueueSize) {
        mutableQueue.removeAt(0);
        logger.info('Queue is full, the oldest event is dropped.');
      }

      mutableQueue.add({'message': prepared});
      setPersistedProperty(PostHogPersistedProperty.queue, mutableQueue);

      events.emit(type, prepared);

      if (mutableQueue.length >= flushAt) {
        _flushBackground();
      }

      if (_flushInterval > 0 && _flushTimer == null) {
        _flushTimer = Timer(Duration(milliseconds: _flushInterval), () {
          _flushBackground();
        });
      }
    });
  }

  Map<String, Object?> _prepareMessage(
    String type,
    Map<String, Object?> message,
    PostHogCaptureOptions? options,
  ) {
    final prepared = <String, Object?>{
      ...message,
      'type': type,
      'library': getLibraryId(),
      'library_version': getLibraryVersion(),
      'timestamp':
          options?.timestamp?.toUtc().toIso8601String() ?? currentISOTime(),
      'uuid': options?.uuid ?? generateUuidV7(),
    };

    final addGeoipDisable = options?.disableGeoip ?? _disableGeoip;
    if (addGeoipDisable) {
      prepared.putIfAbsent('properties', () => <String, Object?>{});
      (prepared['properties'] as Map<String, Object?>)[r'$geoip_disable'] =
          true;
    }

    return prepared;
  }

  void _clearFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void _flushBackground() {
    flush().catchError((e) {
      logger.error('Error while flushing PostHog', e);
    });
  }

  /// Flushes the queue of pending events.
  ///
  /// If a flush is already in progress, returns the existing future to avoid
  /// concurrent flushes sending duplicate events.
  Future<void> flush() {
    if (_flushFuture != null) return _flushFuture!;
    _flushFuture = _doFlush().whenComplete(() => _flushFuture = null);
    return _flushFuture!;
  }

  Future<void> _doFlush() async {
    _clearFlushTimer();

    final sentMessages = <Object?>[];

    while (true) {
      // Re-read from storage each iteration so we see a consistent snapshot
      // that includes any events enqueued during the previous await.
      final queue = List<Object?>.from(
          getPersistedProperty<List<Object?>>(PostHogPersistedProperty.queue) ??
              []);

      if (queue.isEmpty) break;

      final batchItems = queue.take(_maxBatchSize).toList();
      final batchMessages =
          batchItems.map((item) => (item as Map)['message']).toList();

      final data = <String, Object?>{
        'api_key': apiKey,
        'batch': batchMessages,
        'sent_at': currentISOTime(),
      };

      final payload = jsonEncode(data);
      final url = '$host/batch/';

      try {
        await _fetchWithRetry(
          url,
          PostHogFetchOptions(
            method: 'POST',
            headers: {
              ..._getCustomHeaders(),
              'Content-Type': 'application/json',
            },
            body: payload,
          ),
        );
      } catch (e) {
        if (e is PostHogFetchHttpError &&
            e.status == 413 &&
            batchMessages.length > 1) {
          _maxBatchSize = (batchMessages.length ~/ 2).clamp(1, _maxBatchSize);
          logger.warn('Received 413, reducing batch size to $_maxBatchSize');
          continue; // retry with smaller batch
        }

        // Drop sent items from queue on non-network errors (e.g. 400)
        if (e is! PostHogFetchNetworkError) {
          _removeFromFrontOfQueue(batchItems.length);
        }
        // On network errors, leave items in queue for next flush attempt
        events.emit('error', e);
        rethrow;
      }

      // Successfully sent — remove from front of queue
      _removeFromFrontOfQueue(batchItems.length);
      sentMessages.addAll(batchMessages);
    }

    if (sentMessages.isNotEmpty) {
      events.emit('flush', sentMessages);
    }
  }

  /// Removes [count] items from the front of the persisted queue.
  void _removeFromFrontOfQueue(int count) {
    final queue = List<Object?>.from(
        getPersistedProperty<List<Object?>>(PostHogPersistedProperty.queue) ??
            []);
    final removeCount = count.clamp(0, queue.length);
    setPersistedProperty(
        PostHogPersistedProperty.queue, queue.sublist(removeCount));
  }

  Map<String, String> _getCustomHeaders() {
    final userAgent = getCustomUserAgent();
    if (userAgent != null && userAgent.isNotEmpty) {
      return {'User-Agent': userAgent};
    }
    return {};
  }

  Future<PostHogFetchResponse> _fetchWithRetry(
    String url,
    PostHogFetchOptions options, {
    int? retryCount,
    int? timeoutMs,
  }) async {
    return retriable(
      () async {
        PostHogFetchResponse response;
        try {
          response = await fetch(url, options)
              .timeout(Duration(milliseconds: timeoutMs ?? _requestTimeout));
        } catch (e) {
          throw PostHogFetchNetworkError(e);
        }

        if (response.status < 200 || response.status >= 400) {
          throw PostHogFetchHttpError(
            response.status,
            response.body,
            options.body?.length ?? 0,
          );
        }
        return response;
      },
      retryCount: retryCount ?? _fetchRetryCount,
      retryDelay: _fetchRetryDelay,
      retryCheck: _isPostHogFetchError,
    );
  }

  /// Shuts down the PostHog instance and ensures all events are sent.
  Future<void> shutdown({int timeoutMs = 30000}) async {
    _clearFlushTimer();

    await flush().timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () {
        logger.error('Timed out while shutting down PostHog');
      },
    );
  }
}
