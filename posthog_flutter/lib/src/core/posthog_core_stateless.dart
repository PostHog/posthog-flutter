import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:meta/meta.dart';

import '../posthog_config.dart';
import '../posthog_flutter_version.dart';
import 'capture_v1.dart';
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

/// Network failures and the retriable capture v1 statuses are worth
/// retrying; any other status will fail the same way again.
bool _isTransientCaptureError(Object err) =>
    err is PostHogFetchNetworkError ||
    (err is PostHogFetchHttpError && isRetriableCaptureV1Status(err.status));

/// Only transport failures and gateway errors are worth retrying for
/// `/flags`: any other status is the server's answer for this evaluation.
bool _isRetryableFlagsError(Object err) =>
    err is PostHogFetchNetworkError ||
    (err is PostHogFetchHttpError && (err.status == 502 || err.status == 504));

/// The largest fraction a capture retry wait moves either way, so clients
/// refused together don't all come back at the same moment.
const _retryJitter = 0.25;

/// The wait before capture is sent again after the [attempt]-th failure in a
/// row: 1 second doubling up to 30 seconds, scaled by a jitter factor in
/// `[1 - _retryJitter, 1 + _retryJitter)` drawn from [jitterUnit] and capped
/// again. A server [retryAfter], capped at 30 seconds, is a floor applied
/// after the jitter, so a retry never comes earlier than the server asked.
/// A [jitterUnit] outside `[0, 1)` leaves the delay unjittered.
@visibleForTesting
Duration captureRetryDelay({
  required int attempt,
  required double jitterUnit,
  Duration? retryAfter,
}) {
  const initialMs = 1000.0;
  const maxMs = 30000.0;
  final computed =
      min(initialMs * pow(2, (attempt < 1 ? 1 : attempt) - 1), maxMs);
  final factor = jitterUnit >= 0 && jitterUnit < 1
      ? 1 - _retryJitter + 2 * _retryJitter * jitterUnit
      : 1.0;
  final jittered = min(computed * factor, maxMs).round();
  final floor = min(retryAfter?.inMilliseconds ?? 0, maxMs.toInt());
  return Duration(milliseconds: jittered > floor ? jittered : floor);
}

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

  /// How long a request may go without progress: connecting, a chunk of
  /// the body taken by the socket, the response headers, or a chunk of the
  /// response body. A slow but moving upload never times out.
  static const _requestTimeout = Duration(seconds: 10);

  /// The size of the body chunks handed to the socket, each one progress.
  static const _bodyChunkSize = 64 * 1024;

  // A flags request is retried only after a network error or a gateway
  // timeout. A batch is not retried within a flush: the queue backs off.
  static const _flagsRetryCount = 1;
  static const _flagsRetryDelay = Duration(milliseconds: 300);

  /// The [_failedFlushes] at which the backoff reaches its 30 second cap.
  static const _maxBackoffStep = 6;

  /// How many same-origin 307/308 redirects a capture request follows.
  static const _maxCaptureRedirects = 5;

  /// The identity of the last capture request whose events are still to be
  /// retried. Kept in memory: after a restart the retry is a new request.
  CaptureV1Identity? _pendingCaptureIdentity;

  /// Flushes in a row whose batch failed with a transient error or had
  /// events the server asked to retry. Each one pauses the queue for longer,
  /// see [captureRetryDelay], so a failure that lasts, like a missing
  /// capture route, doesn't resend the batch with every capture. A delivered
  /// or dropped batch resets it.
  int _failedFlushes = 0;

  /// The source of the backoff jitter: a uniform value in `[0, 1)`.
  @visibleForTesting
  double Function() jitterUnit = Random().nextDouble;

  /// Whether this client already warned that capture returned a 404.
  bool _warnedCaptureNotFound = false;

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

  final _httpClient = HttpClient()
    ..connectionTimeout = PostHogCoreStateless._requestTimeout;

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
    Map<String, Object?>? options,
  }) {
    _enqueue(
      'capture',
      _buildPayload(
        distinctId: distinctId,
        event: event,
        properties: properties,
      ),
      options: options,
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

  /// Queues [message]. Its capture v1 [options] are queued with it; the
  /// legacy option properties are converted only when the request is built,
  /// see [captureV1Event].
  void _enqueue(
    String type,
    Map<String, Object?> message, {
    Map<String, Object?>? options,
  }) {
    final prepared = <String, Object?>{
      ...message,
      if (message['properties'] case final Map properties)
        'properties': _serializableProperties(properties),
      if (options != null && options.isNotEmpty)
        'options': _serializableProperties(options),
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
          if (toJsonValue(value, logger, dropNullMembers: true)
              case final converted
              when converted != null || key == r'$feature_flag_response')
            '$key': converted,
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

  /// Counts one more failed flush and stops sending events for the backoff
  /// it calls for, at least the server's [retryAfter].
  void _backOff(Duration? retryAfter) {
    if (_failedFlushes < _maxBackoffStep) _failedFlushes++;
    _pauseFlush(captureRetryDelay(
      attempt: _failedFlushes,
      jitterUnit: jitterUnit(),
      retryAfter: retryAfter,
    ));
  }

  /// Stops sending events for [delay].
  void _pauseFlush(Duration delay) {
    _clearFlushTimer();
    _retryAfterTimer?.cancel();
    _retryAfterTimer = Timer(delay, () {
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

    try {
      while (!_closed) {
        // Peeked again after every request, so events queued in the meantime
        // go out with the same flush.
        final batch = takeCaptureV1Batch(queue.peek(_maxBatchSize));
        if (batch.isEmpty) {
          if (queue.length > 0) _scheduleFlush();
          break;
        }
        if (!await _sendBatch(batch, sentMessages)) break;
      }
    } finally {
      if (sentMessages.isNotEmpty) {
        events.emit('flush', sentMessages);
      }
    }
  }

  /// Sends [batch] to capture v1 and removes from the queue the events that
  /// are done: delivered, or dropped for good. Adds the delivered ones to
  /// [sent].
  ///
  /// Returns whether the flush goes on with the rest of the queue. It stops
  /// while events of [batch] wait for a later retry: the queue backs off,
  /// and sends them again once the pause is over.
  Future<bool> _sendBatch(
    List<PostHogQueuedEvent> batch,
    List<Map<String, Object?>> sent,
  ) async {
    final queue = storage.queue;
    final Set<String> retryUuids;
    final Duration? retryAfter;
    try {
      (:retryUuids, :retryAfter) = await _postCaptureV1(batch);
    } catch (e) {
      if (_closed) rethrow;
      if (e is PostHogFetchHttpError &&
          e.status == HttpStatus.requestEntityTooLarge &&
          batch.length > 1) {
        _maxBatchSize = (batch.length ~/ 2).clamp(1, _maxBatchSize);
        logger.warn('Received 413, reducing batch size to $_maxBatchSize');
        return true;
      }
      if (e is PostHogFetchHttpError &&
          e.status == HttpStatus.notFound &&
          !_warnedCaptureNotFound) {
        _warnedCaptureNotFound = true;
        // Printed even without debug: the events stay queued, and nothing
        // else tells the app that the route is missing.
        debugPrint('[PostHog] [WARN] $captureV1Path returned 404. '
            'Events stay queued and are retried. If you use a reverse '
            'proxy or self-host PostHog, make sure it serves '
            '$captureV1Path.');
      }
      // The pause re-arms the periodic flush: otherwise queued events sit
      // until the next capture (forever in an idle app after an offline
      // failure).
      if (_isTransientCaptureError(e)) {
        _backOff(e is PostHogFetchHttpError ? e.retryAfter : null);
      } else {
        queue.remove([for (final queued in batch) queued.id]);
        _failedFlushes = 0;
        _scheduleFlush();
      }
      events.emit('error', e);
      rethrow;
    }

    final delivered = [
      for (final queued in batch)
        if (!retryUuids.contains(queued.event['uuid'])) queued,
    ];
    // Removed by id: the queue may have changed while the batch was in
    // flight, e.g. its oldest events dropped to make room.
    queue.remove([for (final queued in delivered) queued.id]);
    sent.addAll([for (final queued in delivered) queued.event]);
    if (delivered.length == batch.length) {
      _failedFlushes = 0;
      return true;
    }

    // Counts only: uuids and server details can identify users.
    logger.info('Capture asked to retry ${batch.length - delivered.length} '
        'of ${batch.length} events.');
    _backOff(retryAfter);
    return false;
  }

  /// Posts [batch] to capture v1 and returns the uuids of the events the
  /// server asked to retry, with its `Retry-After`. Every other event was
  /// delivered or dropped for good.
  ///
  /// A 2xx whose per-event results cannot be read, also when the response
  /// fails after its status arrived, counts as delivered: the server stored
  /// the events, and sending them again would store them twice.
  ///
  /// Throws [PostHogFetchHttpError] for a non-2xx status and
  /// [PostHogFetchNetworkError] for a transport failure.
  Future<({Set<String> retryUuids, Duration? retryAfter})> _postCaptureV1(
    List<PostHogQueuedEvent> batch,
  ) async {
    final uuids = {
      for (final queued in batch)
        if (queued.event['uuid'] case final String uuid) uuid,
    };
    final pending = _pendingCaptureIdentity;
    final identity = pending != null && sameUuids(pending.uuids, uuids)
        ? pending.next()
        : CaptureV1Identity(
            uuids: uuids,
            requestId: generateUuidV7(),
            createdAt: currentISOTime(),
          );
    _pendingCaptureIdentity = identity;

    final body = jsonEncode({
      'created_at': identity.createdAt,
      'batch': [
        for (final queued in batch) captureV1Event(queued.event, logger),
      ],
    });
    final headers = {
      HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
      'PostHog-Sdk-Info': '$postHogFlutterSdkName/$postHogFlutterVersion',
      'PostHog-Attempt': '${identity.attempt}',
      'PostHog-Request-Id': identity.requestId,
      'PostHog-Request-Timestamp': currentISOTime(),
    };

    // A transport failure keeps the identity, so the resend reuses it.
    final response = await _fetchCaptureV1(body, headers);

    if (response.status < 200 || response.status >= 300) {
      if (!isRetriableCaptureV1Status(response.status)) {
        _pendingCaptureIdentity = null;
      }
      throw PostHogFetchHttpError(
        response.status,
        response.body ?? '',
        body.length,
        retryAfter: response.retryAfter,
      );
    }

    final results = captureV1Results(response.body, uuids);
    if (results == null) {
      logger.info('Capture returned ${response.status} without readable '
          'per-event results; ${uuids.length} events count as delivered.');
    } else if (results.rejected > 0) {
      logger.warn('Capture dropped ${results.rejected} of ${uuids.length} '
          'events for good.');
    }
    final retryUuids = results?.retry ?? const <String>{};
    _pendingCaptureIdentity =
        retryUuids.isEmpty ? null : identity.withUuids(retryUuids);
    return (retryUuids: retryUuids, retryAfter: response.retryAfter);
  }

  /// Posts a capture v1 [body], following only 307 and 308 redirects to the
  /// origin of the configured host, at most [_maxCaptureRedirects] times,
  /// with the same body and headers. Any other redirect is returned as it
  /// is, and is terminal.
  Future<({int status, String? body, Duration? retryAfter, String? location})>
      _fetchCaptureV1(
    String body,
    Map<String, String> headers,
  ) async {
    final origin = Uri.parse(_host);
    var url = Uri.parse('$_host$captureV1Path');
    for (var redirects = 0;; redirects++) {
      final response = await _fetchOnce(url, body,
          headers: headers, deliveredOnBodyFailure: true);
      if (response.status != 307 && response.status != 308) return response;
      final location = response.location;
      final target = location == null ? null : url.resolve(location);
      if (redirects >= _maxCaptureRedirects ||
          target == null ||
          target.scheme != origin.scheme ||
          target.host.toLowerCase() != origin.host.toLowerCase() ||
          target.port != origin.port) {
        logger.warn('Capture did not follow a ${response.status} redirect.');
        return response;
      }
      url = target;
    }
  }

  /// Posts [body] to [url] and returns the response body, retrying the
  /// failures [retryCheck] accepts.
  Future<String> _fetchWithRetry(
    String url,
    String body, {
    required int retryCount,
    required Duration retryDelay,
    required bool Function(Object error) retryCheck,
  }) async {
    return retriable(
      () async {
        final response = await _fetchOnce(Uri.parse(url), body);
        if (response.status < 200 || response.status >= 300) {
          throw PostHogFetchHttpError(
            response.status,
            response.body ?? '',
            body.length,
            retryAfter: response.retryAfter,
          );
        }
        return response.body ?? '';
      },
      retryCount: retryCount,
      retryDelay: retryDelay,
      retryCheck: (error) => !_closed && retryCheck(error),
    );
  }

  /// Sends one request, aborted once it makes no progress for
  /// [_requestTimeout]. A transport failure is thrown as
  /// [PostHogFetchNetworkError], except, with [deliveredOnBodyFailure], one
  /// that happens after a 2xx status arrived: the response is then returned
  /// without a body.
  Future<
      ({
        int status,
        String? body,
        Duration? retryAfter,
        String? location,
      })> _fetchOnce(
    Uri url,
    String body, {
    Map<String, String> headers = const {},
    bool deliveredOnBodyFailure = false,
  }) async {
    final attempt = _FetchAttempt(_requestTimeout);
    try {
      return await attempt.guard(_fetch(url, body, attempt, headers));
    } catch (e) {
      final status = attempt.status;
      if (deliveredOnBodyFailure &&
          status != null &&
          status >= 200 &&
          status < 300) {
        return (
          status: status,
          body: null,
          retryAfter: attempt.retryAfter,
          location: null,
        );
      }
      throw PostHogFetchNetworkError(e);
    }
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

  Future<
      ({
        int status,
        String? body,
        Duration? retryAfter,
        String? location,
      })> _fetch(
    Uri url,
    String body,
    _FetchAttempt attempt,
    Map<String, String> headers,
  ) async {
    final request = await _httpClient.postUrl(url);
    attempt.attachRequest(request);
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
    headers.forEach(request.headers.set);
    final bytes = utf8.encode(body);
    final List<int> payload;
    if (_compression == PostHogCompression.gzip) {
      request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      payload = gzip.encode(bytes);
    } else {
      payload = bytes;
    }
    request.contentLength = payload.length;
    // In chunks, so the socket taking each one counts as progress: it stops
    // taking them while its buffers are full.
    await request.addStream(() async* {
      for (var start = 0; start < payload.length; start += _bodyChunkSize) {
        attempt.progress();
        yield payload.sublist(
            start, min(start + _bodyChunkSize, payload.length));
      }
    }());

    final response = await request.close();
    attempt.progress();
    final retryAfter =
        _parseRetryAfter(response.headers.value(HttpHeaders.retryAfterHeader));
    attempt
      ..status = response.statusCode
      ..retryAfter = retryAfter;
    final responseBody = await attempt.readBody(response);
    return (
      status: response.statusCode,
      body: responseBody,
      retryAfter: retryAfter,
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  /// Closes the client without sending anything: stops the periodic flush,
  /// aborts the requests in flight, ignores later calls and releases the
  /// storage. Queued events stay on disk for the next client; an in-memory
  /// storage loses them.
  void close() {
    _closed = true;
    _clearFlushTimer();
    _retryAfterTimer?.cancel();
    _retryAfterTimer = null;
    _httpClient.close(force: true);
    storage.close();
  }
}

class _FetchAttempt {
  _FetchAttempt(this._idleTimeout);

  final Duration _idleTimeout;
  final timeout = TimeoutException('PostHog request timed out');
  Timer? _idleTimer;
  void Function()? _onIdle;

  HttpClientRequest? _request;

  /// The status and `Retry-After` of the response, once it has arrived.
  int? status;
  Duration? retryAfter;
  StreamSubscription<String>? _responseSubscription;
  Completer<String>? _responseBody;
  bool _cancelled = false;

  /// Completes with [work], or fails with [timeout] once the request has
  /// made no [progress] for the idle timeout. The request is cancelled
  /// before that failure is reported, so a retry never overlaps it.
  Future<T> guard<T>(Future<T> work) {
    final result = Completer<T>();
    var idle = false;
    _onIdle = () async {
      idle = true;
      await cancel();
      if (!result.isCompleted) result.completeError(timeout);
    };
    progress();
    work.then((value) {
      if (!idle && !result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!idle && !result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future.whenComplete(() => _idleTimer?.cancel());
  }

  /// Restarts the idle timeout.
  void progress() {
    _idleTimer?.cancel();
    if (_cancelled) return;
    final onIdle = _onIdle;
    if (onIdle != null) _idleTimer = Timer(_idleTimeout, onIdle);
  }

  void attachRequest(HttpClientRequest request) {
    progress();
    _request = request;
    if (_cancelled) {
      request.abort(timeout);
      throw timeout;
    }
  }

  Future<String> readBody(HttpClientResponse response) {
    final contents = StringBuffer();
    final body = Completer<String>();
    late final StreamSubscription<String> subscription;
    subscription =
        response.transform(const Utf8Decoder(allowMalformed: true)).listen(
      (chunk) {
        progress();
        contents.write(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!body.isCompleted) body.completeError(error, stackTrace);
      },
      onDone: () {
        if (!body.isCompleted) body.complete(contents.toString());
      },
      cancelOnError: true,
    );
    _responseSubscription = subscription;
    _responseBody = body;
    return body.future.whenComplete(() {
      if (identical(_responseSubscription, subscription)) {
        _responseSubscription = null;
        _responseBody = null;
      }
    });
  }

  Future<void> cancel() async {
    _cancelled = true;
    final responseSubscription = _responseSubscription;
    if (responseSubscription == null) {
      _request?.abort(timeout);
    } else {
      await responseSubscription.cancel();
    }
    final body = _responseBody;
    if (body != null && !body.isCompleted) body.completeError(timeout);
  }
}
