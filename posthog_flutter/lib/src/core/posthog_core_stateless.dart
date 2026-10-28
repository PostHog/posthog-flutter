import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// Base stateless PostHog client: the queue of events, consent, super
/// properties and the requests to PostHog.
abstract class PostHogCoreStateless {
  final String _apiKey;
  final String _host;
  final int _flushAt;
  final Duration _flushInterval;
  final PostHogCompression _compression;

  /// Analytics events, sent to [captureV1Path].
  late final _CaptureLane _analytics;

  /// AI events, sent to [captureV1AiPath] from a queue of their own.
  late final _CaptureLane _ai;

  final bool _defaultOptIn;

  static const _requestTimeout = Duration(seconds: 10);

  // A batch is retried after a transient failure; a flags request only after
  // a network error or a gateway timeout.
  static const _fetchRetryCount = 3;
  static const _fetchRetryDelay = Duration(seconds: 3);
  static const _flagsRetryCount = 1;
  static const _flagsRetryDelay = Duration(milliseconds: 300);

  /// The longest `Retry-After` pause honored for events.
  static const _maxRetryAfter = Duration(seconds: 30);

  /// How many same-origin 307/308 redirects a capture request follows.
  static const _maxCaptureRedirects = 5;

  /// The latest consent decision made through this client. It wins over the
  /// stored one: [clearPersistedOptOut] removes the stored decision while
  /// this client keeps honoring it, and a decision the storage cannot
  /// persist must still apply.
  bool? _optedOutDecision;

  @protected
  late final SimpleEventEmitter events;

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

    final maxBatchSize = config.maxBatchSize < 1 ? 1 : config.maxBatchSize;
    _analytics = _CaptureLane(
      path: captureV1Path,
      queue: storage.queue,
      maxBatchSize: maxBatchSize,
      maxQueueSize: config.maxQueueSize < 1 ? 1 : config.maxQueueSize,
      compression: config.compression,
      timeout: _requestTimeout,
    );
    final aiMaxQueueSize = config.captureAiMaxQueueSize ?? 0;
    final aiTimeout = config.captureAiTimeout ?? Duration.zero;
    final aiMaxEventBytes = config.captureAiMaxEventBytes ?? 0;
    _ai = _CaptureLane(
      path: captureV1AiPath,
      queue: storage.aiQueue,
      maxBatchSize: maxBatchSize,
      maxQueueSize:
          aiMaxQueueSize > 0 ? aiMaxQueueSize : captureAiDefaultMaxQueueSize,
      compression: config.captureAiCompression ?? PostHogCompression.gzip,
      timeout: aiTimeout > Duration.zero ? aiTimeout : captureAiDefaultTimeout,
      maxEventBytes:
          aiMaxEventBytes > 0 && aiMaxEventBytes < captureAiMaxEventBytes
              ? aiMaxEventBytes
              : captureAiMaxEventBytes,
      maxQueueBytes: captureAiMaxQueueBytes,
    );

    for (final lane in [_analytics, _ai]) {
      final queue = lane.queue;
      final overflow = queue.length - lane.maxQueueSize;
      if (overflow > 0) {
        queue.removeOldest(overflow);
      }
      final maxQueueBytes = lane.maxQueueBytes;
      if (maxQueueBytes != null) queue.removeOldestOver(maxQueueBytes);

      // Events left over from a previous run go out with the first periodic
      // flush instead of waiting for the next capture.
      if (queue.length > 0) {
        _scheduleFlush(lane);
      }
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
    // The event's properties win over the SDK's.
    var eventProperties = {
      ...getCommonEventProperties(),
      ...properties,
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
    Map<String, Object?>? options,
  }) {
    _enqueue(
      _analytics,
      'identify',
      _buildPayload(
        distinctId: distinctId,
        event: r'$identify',
        properties: properties,
      ),
      options: options,
    );
  }

  /// Queues [event] and returns its uuid, or null when it is not queued.
  /// With [ai], the event goes to the AI queue, which drops an event over
  /// its size limit.
  @protected
  String? captureStateless(
    String distinctId,
    String event, {
    required Map<String, Object?> properties,
    Map<String, Object?>? options,
    String? timestamp,
    bool ai = false,
  }) {
    return _enqueue(
      ai ? _ai : _analytics,
      'capture',
      _buildPayload(
        distinctId: distinctId,
        event: event,
        properties: properties,
      ),
      options: options,
      timestamp: timestamp,
    );
  }

  @protected
  void aliasStateless(
    String alias,
    String distinctId, {
    required Map<String, Object?> properties,
    Map<String, Object?>? options,
  }) {
    _enqueue(
      _analytics,
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
      options: options,
    );
  }

  @protected
  void groupIdentifyStateless(
    String groupType,
    String groupKey, {
    required String distinctId,
    required Map<String, Object?> eventProperties,
    Map<String, Object?>? groupProperties,
    Map<String, Object?>? options,
  }) {
    _enqueue(
      _analytics,
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
      options: options,
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

  /// Queues [message] on [lane] and returns its uuid, or null when it is
  /// over the lane's event size limit. Its capture v1 [options] are queued
  /// with it; the legacy option properties are converted only when the
  /// request is built, see [captureV1Event].
  String? _enqueue(
    _CaptureLane lane,
    String type,
    Map<String, Object?> message, {
    Map<String, Object?>? options,
    String? timestamp,
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
      'timestamp': timestamp ?? currentISOTime(),
      'uuid': generateUuidV7(),
    };

    // Measured as queued, before compression.
    String? json;
    int? bytes;
    final maxEventBytes = lane.maxEventBytes;
    if (maxEventBytes != null) {
      json = jsonEncode(prepared);
      bytes = utf8.encode(json).length;
      if (bytes > maxEventBytes) {
        // Name and size only: AI properties can hold prompts and media.
        logger.warn('Dropping AI event ${message['event']} of $bytes bytes, '
            'over the $maxEventBytes byte limit.');
        return null;
      }
    }

    final queue = lane.queue;
    final overflow = queue.length - lane.maxQueueSize + 1;
    if (overflow > 0) {
      queue.removeOldest(overflow);
      logger.warn('Queue is full, the oldest event is dropped.');
    }
    queue.add(prepared, json: json, bytes: bytes);
    final maxQueueBytes = lane.maxQueueBytes;
    if (maxQueueBytes != null && queue.removeOldestOver(maxQueueBytes) > 0) {
      logger.warn('Queue is over $maxQueueBytes bytes, the oldest events are '
          'dropped.');
    }

    events.emit(type, prepared);

    if (queue.length >= _flushAt ||
        (bytes != null && queue.bytes >= captureV1MaxBatchBytes)) {
      _flushBackground(lane);
    }

    _scheduleFlush(lane);
    return prepared['uuid'] as String;
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

  void _scheduleFlush(_CaptureLane lane) {
    if (!_closed &&
        lane.retryAfterTimer == null &&
        _flushInterval > Duration.zero &&
        lane.flushTimer == null) {
      lane.flushTimer = Timer(_flushInterval, () {
        // Cleared first: a timer firing during a flush in flight only joins
        // that flush, and a stale reference would block every later re-arm.
        lane.flushTimer = null;
        _flushBackground(lane);
      });
    }
  }

  /// Stops sending the events of [lane] for [delay], the server's
  /// `Retry-After` or the backoff after failed flushes, kept between the
  /// retry delay and [_maxRetryAfter].
  void _pauseFlush(_CaptureLane lane, Duration delay) {
    lane.clearFlushTimer();
    lane.retryAfterTimer?.cancel();
    final pause = delay < _fetchRetryDelay
        ? _fetchRetryDelay
        : (delay > _maxRetryAfter ? _maxRetryAfter : delay);
    lane.retryAfterTimer = Timer(pause, () {
      lane.retryAfterTimer = null;
      if (!_closed && _flushInterval > Duration.zero && lane.queue.length > 0) {
        _flushBackground(lane);
      }
    });
  }

  void _flushBackground(_CaptureLane lane) {
    _flushLane(lane).catchError((e) {
      logger.error('Error while flushing PostHog', e);
    });
  }

  /// Flushes the queues of pending events and AI events.
  /// If a flush is already in progress, returns the existing future to avoid
  /// concurrent flushes sending duplicate events.
  Future<void> flush() async {
    await Future.wait([_flushLane(_analytics), _flushLane(_ai)]);
  }

  Future<void> _flushLane(_CaptureLane lane) {
    final inFlight = lane.flushFuture;
    if (inFlight != null) return inFlight;
    if (lane.retryAfterTimer != null) return Future.value();
    final flush = _doFlush(lane).whenComplete(() => lane.flushFuture = null);
    lane.flushFuture = flush;
    return flush;
  }

  Future<void> _doFlush(_CaptureLane lane) async {
    lane.clearFlushTimer();

    final queue = lane.queue;
    final sentMessages = <Map<String, Object?>>[];

    try {
      while (!_closed) {
        // Peeked again after every request, so events queued in the meantime
        // go out with the same flush.
        final batch = takeCaptureV1Batch(queue.peek(lane.maxBatchSize));
        if (batch.isEmpty) {
          if (queue.length > 0) _scheduleFlush(lane);
          break;
        }
        if (!await _sendBatch(lane, batch, sentMessages)) break;
      }
    } finally {
      if (sentMessages.isNotEmpty) {
        events.emit('flush', sentMessages);
      }
    }
  }

  /// Sends [batch] to capture v1, retrying what is worth it, and removes
  /// from the queue the events that are done: delivered, or dropped for
  /// good. Adds the delivered ones to [sent].
  ///
  /// Returns whether the flush goes on with the rest of the queue. It stops
  /// while events of [batch] wait for a later retry; the periodic flush or
  /// the server's `Retry-After` sends them again.
  Future<bool> _sendBatch(
    _CaptureLane lane,
    List<PostHogQueuedEvent> batch,
    List<Map<String, Object?>> sent,
  ) async {
    final queue = lane.queue;
    var pending = batch;
    for (var attempt = 0;; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_fetchRetryDelay);
        // A client closed meanwhile leaves the queue to the next one.
        if (_closed) return false;
      }

      final Set<String> retryUuids;
      final Duration? retryAfter;
      try {
        (:retryUuids, :retryAfter) = await _postCaptureV1(lane, pending);
        lane.failedFlushes = 0;
      } catch (e) {
        if (_closed) rethrow;
        if (e is PostHogFetchHttpError &&
            e.status == HttpStatus.requestEntityTooLarge &&
            pending.length > 1) {
          lane.maxBatchSize = (pending.length ~/ 2).clamp(1, lane.maxBatchSize);
          logger.warn(
              'Received 413, reducing batch size to ${lane.maxBatchSize}');
          return true;
        }
        if (e is PostHogFetchHttpError &&
            e.status == HttpStatus.notFound &&
            !lane.warnedNotFound) {
          lane.warnedNotFound = true;
          // Printed even without debug: the events stay queued, and nothing
          // else tells the app that the route is missing.
          debugPrint('[PostHog] [WARN] ${lane.path} returned 404. '
              'Events stay queued and are retried. If you use a reverse '
              'proxy or self-host PostHog, make sure it serves '
              '${lane.path}.');
        }
        final transient = _isTransientCaptureError(e);
        final retryAfter = e is PostHogFetchHttpError ? e.retryAfter : null;
        if (transient &&
            retryAfter == null &&
            lane.failedFlushes == 0 &&
            attempt < _fetchRetryCount) {
          continue;
        }
        if (!transient) {
          queue.remove([for (final queued in pending) queued.id]);
        }
        // Re-arm the periodic flush: otherwise queued events sit until the
        // next capture (forever in an idle app after an offline failure).
        if (transient && retryAfter != null) {
          _pauseFlush(lane, retryAfter);
        } else if (transient) {
          lane.failedFlushes++;
          _pauseFlush(
              lane, _fetchRetryDelay * (1 << lane.failedFlushes.clamp(1, 4)));
        } else {
          _scheduleFlush(lane);
        }
        events.emit('error', e);
        rethrow;
      }

      final retained = [
        for (final queued in pending)
          if (retryUuids.contains(queued.event['uuid'])) queued,
      ];
      final delivered = [
        for (final queued in pending)
          if (!retryUuids.contains(queued.event['uuid'])) queued,
      ];
      // Removed by id: the queue may have changed while the batch was in
      // flight, e.g. its oldest events dropped to make room.
      queue.remove([for (final queued in delivered) queued.id]);
      sent.addAll([for (final queued in delivered) queued.event]);
      if (retained.isEmpty) return true;

      // Counts only: uuids and server details can identify users.
      logger.info('Capture asked to retry ${retained.length} of '
          '${pending.length} events.');
      pending = retained;
      if (retryAfter != null) {
        _pauseFlush(lane, retryAfter);
        return false;
      }
      if (attempt >= _fetchRetryCount) {
        _scheduleFlush(lane);
        return false;
      }
    }
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
    _CaptureLane lane,
    List<PostHogQueuedEvent> batch,
  ) async {
    final uuids = {
      for (final queued in batch)
        if (queued.event['uuid'] case final String uuid) uuid,
    };
    final pending = lane.pendingIdentity;
    final identity = pending != null && sameUuids(pending.uuids, uuids)
        ? pending.next()
        : CaptureV1Identity(
            uuids: uuids,
            requestId: generateUuidV7(),
            createdAt: currentISOTime(),
          );
    lane.pendingIdentity = identity;

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
    final response = await _fetchCaptureV1(lane, body, headers);

    if (response.status < 200 || response.status >= 300) {
      if (!isRetriableCaptureV1Status(response.status)) {
        lane.pendingIdentity = null;
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
    lane.pendingIdentity =
        retryUuids.isEmpty ? null : identity.withUuids(retryUuids);
    return (retryUuids: retryUuids, retryAfter: response.retryAfter);
  }

  /// Posts a capture v1 [body], following only 307 and 308 redirects to the
  /// origin of the configured host, at most [_maxCaptureRedirects] times,
  /// with the same body and headers. Any other redirect is returned as it
  /// is, and is terminal.
  Future<({int status, String? body, Duration? retryAfter, String? location})>
      _fetchCaptureV1(
    _CaptureLane lane,
    String body,
    Map<String, String> headers,
  ) async {
    final origin = Uri.parse(_host);
    var url = Uri.parse('$_host${lane.path}');
    for (var redirects = 0;; redirects++) {
      final response = await _fetchOnce(url, body,
          headers: headers,
          deliveredOnBodyFailure: true,
          timeout: lane.timeout,
          compression: lane.compression);
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

  /// Sends one request, bounded by [timeout], [_requestTimeout] by default,
  /// and compressed with [compression], the configured one by default. A
  /// transport failure
  /// is thrown as [PostHogFetchNetworkError], except, with
  /// [deliveredOnBodyFailure], one that happens after a 2xx status arrived:
  /// the response is then returned without a body.
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
    Duration timeout = _requestTimeout,
    PostHogCompression? compression,
  }) async {
    final attempt = _FetchAttempt();
    try {
      return await _fetch(
              url, body, attempt, headers, compression ?? _compression)
          .timeout(
        timeout,
        onTimeout: () async {
          await attempt.cancel();
          throw attempt.timeout;
        },
      );
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
    PostHogCompression compression,
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
    if (compression == PostHogCompression.gzip) {
      request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      payload = gzip.encode(bytes);
    } else {
      payload = bytes;
    }
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
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
    for (final lane in [_analytics, _ai]) {
      lane.clearFlushTimer();
      lane.retryAfterTimer?.cancel();
      lane.retryAfterTimer = null;
    }
    _httpClient.close(force: true);
    storage.close();
  }
}

/// A queue of events and the state of sending it to one capture v1
/// endpoint.
class _CaptureLane {
  _CaptureLane({
    required this.path,
    required this.queue,
    required this.maxBatchSize,
    required this.maxQueueSize,
    required this.compression,
    required this.timeout,
    this.maxEventBytes,
    this.maxQueueBytes,
  });

  final String path;
  final FileEventQueue queue;

  /// Lowered by a 413.
  int maxBatchSize;
  final int maxQueueSize;
  final PostHogCompression compression;
  final Duration timeout;

  /// The largest serialized event queued; null for no limit.
  final int? maxEventBytes;

  /// The most serialized event bytes kept queued; null for no limit.
  final int? maxQueueBytes;

  /// The identity of the last request whose events are still to be
  /// retried. Kept in memory: after a restart the retry is a new request.
  CaptureV1Identity? pendingIdentity;

  /// Flushes in a row whose batch failed with a transient error. Once one
  /// has failed, later flushes send once and wait longer, so a failure that
  /// lasts, like a missing capture route, doesn't resend the batch with
  /// every capture. A delivered batch resets it.
  int failedFlushes = 0;

  /// Whether this client already warned that [path] returned a 404.
  bool warnedNotFound = false;

  Timer? flushTimer;
  Timer? retryAfterTimer;
  Future<void>? flushFuture;

  void clearFlushTimer() {
    flushTimer?.cancel();
    flushTimer = null;
  }
}

class _FetchAttempt {
  final timeout = TimeoutException('PostHog request timed out');

  HttpClientRequest? _request;

  /// The status and `Retry-After` of the response, once it has arrived.
  int? status;
  Duration? retryAfter;
  StreamSubscription<String>? _responseSubscription;
  Completer<String>? _responseBody;
  bool _cancelled = false;

  void attachRequest(HttpClientRequest request) {
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
      contents.write,
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
