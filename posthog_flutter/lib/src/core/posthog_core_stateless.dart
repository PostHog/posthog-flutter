import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../posthog_config.dart';
import '../posthog_flutter_version.dart';
import 'event_emitter.dart';
import 'feature_flag_utils.dart';
import 'feature_flags.dart';
import 'file_storage.dart';
import 'logger.dart';
import 'persistence.dart';
import 'utils/utils.dart';
import 'uuid.dart';

/// HTTP error during PostHog fetch.
class PostHogFetchHttpError implements Exception {
  final int status;
  final String responseBody;
  final int reqByteLength;
  final Duration? retryAfter;

  PostHogFetchHttpError(this.status, this.responseBody, this.reqByteLength,
      {this.retryAfter});

  @override
  String toString() => 'PostHogFetchHttpError: status=$status, '
      'reqByteLength=$reqByteLength, response=$responseBody';
}

/// Network error during PostHog fetch.
class PostHogFetchNetworkError implements Exception {
  final Object? cause;
  PostHogFetchNetworkError(this.cause);

  @override
  String toString() => 'PostHogFetchNetworkError: $cause';
}

/// Network failures and transient HTTP statuses are worth retrying;
/// hard 4xx (invalid token, bad payload) will fail the same way again.
/// A redirect is not followed for a POST, so the batch never reached
/// ingestion and stays queued.
bool _isTransientFetchError(Object err) =>
    err is PostHogFetchNetworkError ||
    (err is PostHogFetchHttpError &&
        (err.status >= 500 ||
            err.status == 429 ||
            err.status == 408 ||
            (err.status >= 300 && err.status < 400)));

/// Only transport failures and gateway errors are worth retrying for
/// `/flags`: any other status is the server's answer for this evaluation.
bool _isRetryableFlagsError(Object err) =>
    err is PostHogFetchNetworkError ||
    (err is PostHogFetchHttpError && (err.status == 502 || err.status == 504));

/// Base stateless PostHog client: the queue of events, consent, super
/// properties and the requests to PostHog.
abstract class PostHogCoreStateless {
  final String _apiKey;
  final String _host;
  final int _flushAt;
  int _maxBatchSize;
  final int _maxQueueSize;
  final Duration _flushInterval;
  final PostHogCompression _compression;

  final bool _defaultOptIn;

  static const _requestTimeout = Duration(seconds: 10);

  // A batch is retried after a transient failure; a flags request only after
  // a network error or a gateway timeout.
  static const _fetchRetryCount = 3;
  static const _fetchRetryDelay = Duration(seconds: 3);
  static const _flagsRetryCount = 1;
  static const _flagsRetryDelay = Duration(milliseconds: 300);

  /// The latest consent decision made through this client. It wins over the
  /// stored one: [clearPersistedOptOut] removes the stored decision while
  /// this client keeps honoring it, and a decision the storage cannot
  /// persist must still apply.
  bool? _optedOutDecision;

  @protected
  late final SimpleEventEmitter events;
  Timer? _flushTimer;
  Timer? _retryAfterTimer;
  Future<void>? _flushFuture;

  /// Set by [close]: later calls are ignored, the periodic flush stops, and
  /// a failed request is not retried.
  bool _closed = false;
  @protected
  late final CoreLogger logger;
  void Function()? _removeDebugCallback;

  /// Where the client keeps its state and the events waiting to be sent.
  @protected
  final FileStorage storage;

  final _httpClient = HttpClient();

  PostHogCoreStateless(
    PostHogConfig config, {
    required this.storage,
  })  : _apiKey = config.projectToken,
        _host = removeTrailingSlash(config.host),
        _flushAt = config.flushAt < 1 ? 1 : config.flushAt,
        _maxBatchSize = config.maxBatchSize < 1 ? 1 : config.maxBatchSize,
        _maxQueueSize = config.maxQueueSize < 1 ? 1 : config.maxQueueSize,
        _flushInterval = config.flushInterval,
        _compression = config.compression,
        _defaultOptIn = !config.optOut {
    logger = CoreLogger(_logMsgIfDebug);
    events = SimpleEventEmitter(
        onListenerError: (e) => logger.warn('Error in event listener:', e));
    storage.logger = logger;
    if (config.debug) {
      debug(true);
    }

    final queue = storage.queue;
    final overflow = queue.length - _maxQueueSize;
    if (overflow > 0) {
      queue.removeOldest(overflow);
    }

    // Events left over from a previous run go out with the first periodic
    // flush instead of waiting for the next capture.
    if (queue.length > 0) {
      _scheduleFlush();
    }
  }

  bool get _isDebug => _removeDebugCallback != null;

  void _logMsgIfDebug(void Function() fn) {
    if (_isDebug) {
      fn();
    }
  }

  /// Runs [fn] and returns its result, or skips it and returns null when
  /// the client is closed.
  @protected
  T? wrap<T>(T Function() fn) {
    if (_closed) {
      logger.info('The client is closed, ignoring the call.');
      return null;
    }
    return fn();
  }

  /// Gets common event properties.
  @protected
  Map<String, Object?> getCommonEventProperties() {
    return {
      r'$lib': postHogFlutterSdkName,
      r'$lib_version': postHogFlutterVersion,
    };
  }

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
      _optedOutDecision ??
      getPersistedProperty<bool>(PostHogPersistedProperty.optedOut) ??
      // Unknown consent while the store is unreadable: fail closed.
      (storage.isDegraded || !_defaultOptIn);

  /// Opt in to tracking.
  void optIn() {
    wrap(() => _decideOptOut(false));
  }

  /// Opt out of tracking.
  void optOut() {
    wrap(() => _decideOptOut(true));
  }

  void _decideOptOut(bool optedOut) {
    _optedOutDecision = optedOut;
    setPersistedProperty(PostHogPersistedProperty.optedOut, optedOut);
  }

  /// Removes the persisted consent decision, so the next client starts from
  /// the configured default. This client keeps honoring the decision until
  /// it is recreated: a reset never silently re-enables tracking.
  @protected
  void clearPersistedOptOut() {
    _optedOutDecision = optedOut;
    setPersistedProperty(PostHogPersistedProperty.optedOut, null);
  }

  /// Enables or disables debug mode.
  void debug(bool enabled) {
    _removeDebugCallback?.call();
    _removeDebugCallback = null;

    if (enabled) {
      _removeDebugCallback =
          events.onAny((event, payload) => logger.info(event, payload));
    }
  }

  Map<String, Object?> _buildPayload({
    required String distinctId,
    required String event,
    required Map<String, Object?> properties,
  }) {
    var eventProperties = {
      ...properties,
      ...getCommonEventProperties(),
    };
    // Minimized once all SDK properties are in.
    if (event == r'$feature_flag_called' &&
        eventProperties[r'$feature_flag_has_experiment'] == false &&
        isMinimalFlagCalledEventsEnabled()) {
      eventProperties = {
        for (final entry in eventProperties.entries)
          if (minimalFeatureFlagCalledProperties.contains(entry.key))
            entry.key: entry.value,
      };
    }
    return {
      'distinct_id': distinctId,
      'event': event,
      'properties': eventProperties,
    };
  }

  /// Whether the server asked for minimal `$feature_flag_called` events.
  @protected
  bool isMinimalFlagCalledEventsEnabled();

  @protected
  void identifyStateless(
    String distinctId, {
    required Map<String, Object?> properties,
  }) {
    _enqueue(
      'identify',
      _buildPayload(
        distinctId: distinctId,
        event: r'$identify',
        properties: properties,
      ),
    );
  }

  @protected
  void captureStateless(
    String distinctId,
    String event, {
    required Map<String, Object?> properties,
  }) {
    _enqueue(
      'capture',
      _buildPayload(
        distinctId: distinctId,
        event: event,
        properties: properties,
      ),
    );
  }

  @protected
  void aliasStateless(
    String alias,
    String distinctId, {
    required Map<String, Object?> properties,
  }) {
    _enqueue(
      'alias',
      _buildPayload(
        distinctId: distinctId,
        event: r'$create_alias',
        properties: {
          ...properties,
          'distinct_id': distinctId,
          'alias': alias,
        },
      ),
    );
  }

  @protected
  void groupIdentifyStateless(
    String groupType,
    String groupKey, {
    required String distinctId,
    required Map<String, Object?> eventProperties,
    Map<String, Object?>? groupProperties,
  }) {
    _enqueue(
      'capture',
      _buildPayload(
        distinctId: distinctId,
        event: r'$groupidentify',
        properties: {
          r'$group_type': groupType,
          r'$group_key': groupKey,
          r'$group_set': groupProperties ?? {},
          ...eventProperties,
        },
      ),
    );
  }

  @protected
  Future<GetFlagsResult> getFlags(
    String distinctId, {
    required Map<String, Object> groups,
    // The /flags API accepts arbitrary JSON property values (bool/int/...),
    // so the parameters must not force String values.
    required Map<String, Object?> personProperties,
    required Map<String, Map<String, Object?>> groupProperties,
    required Map<String, Object?> extraPayload,
  }) async {
    final url = '$_host/flags/?v=2&config=true';

    final requestData = <String, Object?>{
      'token': _apiKey,
      'distinct_id': distinctId,
      'groups': groups,
      'person_properties': personProperties,
      'group_properties': groupProperties,
      ...extraPayload,
    };

    logger.info('Flags URL', url);

    try {
      final response = await _fetchWithRetry(
        url,
        jsonEncode(requestData),
        retryCount: _flagsRetryCount,
        retryDelay: _flagsRetryDelay,
        retryCheck: _isRetryableFlagsError,
      );
      final json = jsonDecode(response) as Map<String, Object?>;
      return GetFlagsSuccess(parseFlagsResponse(json,
          onMalformedFlag: (key, e) =>
              logger.warn('Skipping malformed feature flag "$key":', e)));
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
  Map<String, Object?> get props {
    return getPersistedProperty<Map<String, Object?>>(
            PostHogPersistedProperty.props) ??
        {};
  }

  void register(Map<String, Object?> properties) {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.props,
          {...props, ...toJsonMap(properties, logger)});
    });
  }

  void unregister(String property) {
    wrap(() {
      final updated = {...props}..remove(property);
      setPersistedProperty(PostHogPersistedProperty.props, updated);
    });
  }

  void _enqueue(String type, Map<String, Object?> message) {
    final prepared = <String, Object?>{
      ...message,
      if (message['properties'] case final Map properties)
        'properties': _serializableProperties(properties),
      'type': type,
      'library': postHogFlutterSdkName,
      'library_version': postHogFlutterVersion,
      'timestamp': currentISOTime(),
      'uuid': generateUuidV7(),
    };
    final queue = storage.queue;
    final overflow = queue.length - _maxQueueSize + 1;
    if (overflow > 0) {
      queue.removeOldest(overflow);
      logger.warn('Queue is full, the oldest event is dropped.');
    }
    queue.add(prepared);

    events.emit(type, prepared);

    if (queue.length >= _flushAt) {
      _flushBackground();
    }

    _scheduleFlush();
  }

  /// The event properties as they are queued and sent: values JSON cannot
  /// represent are converted, and null-valued object members are left out,
  /// as the capture spec requires. Null keeps its meaning only in the
  /// `$feature_flag_response` of a flag that has no value.
  Map<String, Object?> _serializableProperties(
          Map<Object?, Object?> properties) =>
      {
        for (final MapEntry(:key, :value) in properties.entries)
          if (value != null || key == r'$feature_flag_response')
            '$key': toJsonValue(value, logger, dropNullMembers: true),
      };

  void _scheduleFlush() {
    if (!_closed &&
        _retryAfterTimer == null &&
        _flushInterval > Duration.zero &&
        _flushTimer == null) {
      _flushTimer = Timer(_flushInterval, () {
        // Cleared first: a timer firing during a flush in flight only joins
        // that flush, and a stale reference would block every later re-arm.
        _flushTimer = null;
        _flushBackground();
      });
    }
  }

  void _clearFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void _pauseFlush(Duration delay) {
    _clearFlushTimer();
    _retryAfterTimer?.cancel();
    _retryAfterTimer =
        Timer(delay < _fetchRetryDelay ? _fetchRetryDelay : delay, () {
      _retryAfterTimer = null;
      if (!_closed &&
          _flushInterval > Duration.zero &&
          storage.queue.length > 0) {
        _flushBackground();
      }
    });
  }

  void _flushBackground() {
    flush().catchError((e) {
      logger.error('Error while flushing PostHog', e);
    });
  }

  /// Flushes the queue of pending events.
  /// If a flush is already in progress, returns the existing future to avoid
  /// concurrent flushes sending duplicate events.
  Future<void> flush() {
    if (_flushFuture != null) return _flushFuture!;
    if (_retryAfterTimer != null) return Future.value();
    _flushFuture = _doFlush().whenComplete(() => _flushFuture = null);
    return _flushFuture!;
  }

  Future<void> _doFlush() async {
    _clearFlushTimer();

    final queue = storage.queue;
    final sentMessages = <Map<String, Object?>>[];

    while (!_closed) {
      // Peeked again after every request, so events queued in the meantime
      // go out with the same flush.
      final batch = queue.peek(_maxBatchSize);
      if (batch.isEmpty) break;
      final batchMessages = [for (final queued in batch) queued.event];

      final data = <String, Object?>{
        'api_key': _apiKey,
        'batch': batchMessages,
        'sent_at': currentISOTime(),
      };

      final payload = jsonEncode(data);
      final url = '$_host/batch/';

      try {
        await _fetchWithRetry(url, payload, honorRetryAfter: true);
      } catch (e) {
        // A client closed meanwhile leaves the queue to the next one.
        if (_closed) rethrow;
        if (e is PostHogFetchHttpError &&
            e.status == 413 &&
            batchMessages.length > 1) {
          _maxBatchSize = (batchMessages.length ~/ 2).clamp(1, _maxBatchSize);
          logger.warn('Received 413, reducing batch size to $_maxBatchSize');
          continue;
        }

        if (!_isTransientFetchError(e)) {
          queue.remove([for (final queued in batch) queued.id]);
        }
        // Re-arm the periodic flush: otherwise queued events sit until the
        // next capture (forever in an idle app after an offline failure).
        if (_isTransientFetchError(e) &&
            e is PostHogFetchHttpError &&
            e.retryAfter != null) {
          _pauseFlush(e.retryAfter!);
        } else {
          _scheduleFlush();
        }
        events.emit('error', e);
        rethrow;
      }

      // Removed by id: the queue may have changed while the batch was in
      // flight, e.g. its oldest events dropped to make room.
      queue.remove([for (final queued in batch) queued.id]);
      sentMessages.addAll(batchMessages);
    }

    if (sentMessages.isNotEmpty) {
      events.emit('flush', sentMessages);
    }
  }

  /// Posts [body] to [url] and returns the response body, retrying the
  /// failures [retryCheck] accepts.
  Future<String> _fetchWithRetry(
    String url,
    String body, {
    int retryCount = _fetchRetryCount,
    Duration retryDelay = _fetchRetryDelay,
    bool Function(Object error) retryCheck = _isTransientFetchError,
    bool honorRetryAfter = false,
  }) async {
    return retriable(
      () async {
        final ({int status, String body, Duration? retryAfter}) response;
        try {
          response = await _fetch(url, body).timeout(_requestTimeout);
        } catch (e) {
          throw PostHogFetchNetworkError(e);
        }

        if (response.status < 200 || response.status >= 300) {
          throw PostHogFetchHttpError(
            response.status,
            response.body,
            body.length,
            retryAfter: response.retryAfter,
          );
        }
        return response.body;
      },
      retryCount: retryCount,
      retryDelay: retryDelay,
      retryCheck: (error) =>
          !_closed &&
          retryCheck(error) &&
          !(honorRetryAfter &&
              error is PostHogFetchHttpError &&
              error.retryAfter != null),
    );
  }

  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    final Duration delay;
    if (seconds != null) {
      delay = Duration(seconds: seconds);
    } else {
      try {
        delay = HttpDate.parse(value).difference(DateTime.now().toUtc());
      } on HttpException {
        return null;
      }
    }
    return delay > Duration.zero ? delay : null;
  }

  Future<({int status, String body, Duration? retryAfter})> _fetch(
      String url, String body) async {
    final request = await _httpClient.postUrl(Uri.parse(url));
    // A redirect is reported rather than followed, so a redirected batch is
    // not taken for delivered.
    request.followRedirects = false;
    // PostHog infers the flag evaluation runtime from the User-Agent: an
    // agent it does not recognize as a client SDK receives no client-only
    // flags.
    request.headers
      ..set(HttpHeaders.userAgentHeader,
          '$postHogFlutterSdkName/$postHogFlutterVersion')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    final bytes = utf8.encode(body);
    final List<int> payload;
    if (_compression == PostHogCompression.gzip) {
      request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      payload = gzip.encode(bytes);
    } else {
      payload = bytes;
    }
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
    final responseBody = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    return (
      status: response.statusCode,
      body: responseBody,
      retryAfter: _parseRetryAfter(
          response.headers.value(HttpHeaders.retryAfterHeader)),
    );
  }

  /// Closes the client without sending anything: stops the periodic flush,
  /// aborts the requests in flight, ignores later calls and releases the
  /// storage. Queued events stay stored for the next client.
  void close() {
    _closed = true;
    _clearFlushTimer();
    _retryAfterTimer?.cancel();
    _retryAfterTimer = null;
    _httpClient.close(force: true);
    storage.close();
  }
}
