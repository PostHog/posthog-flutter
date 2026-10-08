import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

import '../feature_flag_result.dart';
import '../posthog_config.dart';
import 'feature_flag_utils.dart';
import 'feature_flags.dart';
import 'persistence.dart';
import 'posthog_core_stateless.dart';
import 'session_manager.dart';
import 'utils/utils.dart';
import 'uuid.dart';

/// Stateful PostHog client with session management, identity, and feature flags.
///
/// It extends [PostHogCoreStateless] with state management for sessions,
/// identity, feature flags, and person profiles.
abstract class PostHogCore extends PostHogCoreStateless {
  final bool _sendFeatureFlagEvents;
  final PostHogPersonProfiles _personProfiles;

  /// The `$feature_flag_called` values already reported, per flag key.
  final Map<String, Set<PostHogFeatureFlagValue?>> _flagCallReported = {};

  /// Whether a /flags request is in flight.
  bool _loadingFlags = false;

  /// The reload that waits for the /flags request in flight.
  Completer<void>? _pendingFlagsReload;

  /// Changes when reset invalidates responses requested for the previous user.
  int _featureFlagsGeneration = 0;

  final _session = PostHogSessionManager();

  /// See [registerForSession].
  final Map<String, Object?> _sessionProps = {};

  /// The person properties sent last, so that a duplicate `$set` is skipped.
  String? _cachedPersonProperties;

  Map<String, PostHogFeatureFlagValue> _bootstrappedFlags = const {};
  Map<String, Object?> _bootstrappedPayloads = const {};

  /// Whether a `/flags` request has succeeded since the client started or
  /// was reset, quota-limited or not. `$used_bootstrap_value` reports the
  /// opposite.
  bool _flagsLoadedFromRemote = false;

  /// Whether the flags listeners have been told the outcome of a `/flags`
  /// request.
  bool _flagsRequestAnnounced = false;

  PostHogCore(PostHogConfig config, {required super.storage})
      : _sendFeatureFlagEvents = config.sendFeatureFlagEvents,
        _personProfiles = config.personProfiles,
        super(config) {
    final bootstrap = config.bootstrap;
    if (bootstrap != null) _seedBootstrapIdentity(bootstrap);
    // Seeded before identify() or reset() can rotate the anonymous id.
    _getDeviceId();
    if (bootstrap != null) {
      _seedBootstrapFlags(bootstrap);
      _reconcileBootstrapIdentity(bootstrap);
    }
    _announceStartupFlags();
    if (config.preloadFeatureFlags) _reloadFeatureFlags();
  }

  /// Resets the PostHog state. Clears all persisted properties except the
  /// device id, and starts a new session. Queued events are kept.
  ///
  /// The persisted opt-out is cleared too, so the next client starts from
  /// the configured default; this client keeps the current consent decision.
  void reset() {
    wrap(() {
      _featureFlagsGeneration++;
      _sessionProps.clear();
      _flagCallReported.clear();
      _cachedPersonProperties = null;
      _bootstrappedFlags = const {};
      _bootstrappedPayloads = const {};
      _flagsLoadedFromRemote = false;

      clearPersistedOptOut();
      for (final property in PostHogPersistedProperty.values) {
        // Device-level flag bucketing must not change with the user.
        if (property != PostHogPersistedProperty.deviceId &&
            property != PostHogPersistedProperty.optedOut) {
          setPersistedProperty(property, null);
        }
      }

      _session.restart();
      _reloadFeatureFlags();
    });
  }

  @override
  Map<String, Object?> getCommonEventProperties() {
    final featureFlags = _getFeatureFlags() ?? const {};
    final activeFeatureFlags = [
      for (final entry in featureFlags.entries)
        if (entry.value != false) entry.key,
    ];

    return {
      if (activeFeatureFlags.isNotEmpty)
        r'$active_feature_flags': activeFeatureFlags,
      for (final entry in featureFlags.entries)
        '\$feature/${entry.key}': entry.value,
      ...super.getCommonEventProperties(),
    };
  }

  @override
  bool isMinimalFlagCalledEventsEnabled() =>
      _getStoredFlagDetails()?.minimalFlagCalledEvents == true;

  /// Platform context (OS, app, device) attached to every event. It wins
  /// over registered and event properties of the same name: it describes
  /// the environment the SDK runs in.
  @protected
  Map<String, Object?> getContextProperties();

  /// Default person properties sent with every feature flag evaluation
  /// request. Explicitly set person properties override them.
  @protected
  Map<String, Object?> getDefaultPersonPropertiesForFlags();

  /// The IANA time zone id of the device, for example `Europe/Berlin`, or
  /// null when it is unknown. Sent as `$timezone` with every event, as part
  /// of the platform context, and as `timezone` with feature flag requests.
  /// Called for every event, so it should be cheap.
  @protected
  String? getTimezone();

  Map<String, Object?> _enrichProperties(Map<String, Object?>? properties) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Resolved first: it may start a new session, which the debug
    // properties below then describe.
    final managedSessionId = _session.touch(now);
    final callerSessionId = properties?[r'$session_id'];
    final sessionId = callerSessionId is String && callerSessionId.isNotEmpty
        ? callerSessionId
        : managedSessionId;
    final timezone = getTimezone();
    return {
      ...props,
      ..._sessionProps,
      ...?properties,
      ...getContextProperties(),
      if (timezone != null) r'$timezone': timezone,
      ...getCommonEventProperties(),
      r'$session_id': sessionId,
      r'$process_person_profile': _hasPersonProcessing(),
      r'$is_identified': _isIdentified(),
      ..._sessionDebugProperties(now),
    };
  }

  /// The state of the session and the queue, attached to every event to
  /// help debug the SDK.
  Map<String, Object?> _sessionDebugProperties(int now) {
    final startedAt = _session.startedAt;
    return {
      r'$sdk_debug_session_start': startedAt,
      // The wall clock can move backwards.
      r'$sdk_debug_current_session_duration': max(0, now - startedAt),
      r'$sdk_debug_pending_queue_size': storage.queue.length,
    };
  }

  /// Adds [properties] to every later event until [reset], without
  /// persisting them. They win over registered properties, and the event's
  /// own properties win over them.
  void registerForSession(Map<String, Object?> properties) {
    wrap(() => _sessionProps.addAll(properties));
  }

  /// Returns the current session ID.
  ///
  /// Reading the id neither extends nor ends the session; events do. A
  /// session also ends on [reset], and when a new client is created.
  String getSessionId() => _session.id;

  String _getAnonymousId() {
    var anonId =
        getPersistedProperty<String>(PostHogPersistedProperty.anonymousId);
    if (anonId == null) {
      anonId = generateUuidV7();
      setPersistedProperty(PostHogPersistedProperty.anonymousId, anonId);
    }
    return anonId;
  }

  /// Returns the current distinct ID.
  String getDistinctId() {
    return getPersistedProperty<String>(PostHogPersistedProperty.distinctId) ??
        _getAnonymousId();
  }

  /// The id used for device-level flag bucketing: the first anonymous id,
  /// kept through identify() and reset().
  String _getDeviceId() {
    var deviceId =
        getPersistedProperty<String>(PostHogPersistedProperty.deviceId);
    if (deviceId == null) {
      deviceId = _getAnonymousId();
      setPersistedProperty(PostHogPersistedProperty.deviceId, deviceId);
    }
    return deviceId;
  }

  /// Seeds the bootstrapped identity on a fresh install only: once anything
  /// is persisted, the stored identity wins.
  void _seedBootstrapIdentity(PostHogBootstrapConfig bootstrap) {
    final distinctId = bootstrap.distinctId;
    if (distinctId == null || distinctId.trim().isEmpty) {
      if (bootstrap.isIdentifiedId) {
        logger.warn('bootstrap.isIdentifiedId is true, but distinctId is '
            'empty. The identified bootstrap is ignored.');
      }
      return;
    }
    if (getPersistedProperty<String>(PostHogPersistedProperty.anonymousId) !=
            null ||
        getPersistedProperty<String>(PostHogPersistedProperty.distinctId) !=
            null) {
      return;
    }

    if (bootstrap.isIdentifiedId) {
      // The anonymous (and so the device) id is still generated as usual:
      // device-level bucketing must never use the person's id.
      setPersistedProperty(PostHogPersistedProperty.distinctId, distinctId);
      setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
    } else {
      setPersistedProperty(PostHogPersistedProperty.anonymousId, distinctId);
    }
  }

  /// Reconciles an identified bootstrap with the user already stored on
  /// this device.
  void _reconcileBootstrapIdentity(PostHogBootstrapConfig bootstrap) {
    final distinctId = bootstrap.distinctId;
    if (!bootstrap.isIdentifiedId ||
        distinctId == null ||
        distinctId.trim().isEmpty) {
      return;
    }

    if (getDistinctId() == distinctId) {
      // Nothing to merge: the stored anonymous id already is this user.
      if (!_isIdentified()) {
        setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
      }
    } else if (_isIdentified()) {
      logger.warn('bootstrap.distinctId differs from the identified user '
          'stored on this device, which is kept. Call reset() before '
          'creating the client to switch users.');
    } else if (optedOut) {
      // identify() ignores calls while opted out, but opting out only stops
      // events: the identity is still reconciled for a later opt-in.
      if (_personProfiles != PostHogPersonProfiles.never) {
        setPersistedProperty(PostHogPersistedProperty.distinctId, distinctId);
        setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
      }
    } else {
      identify(distinctId);
    }
  }

  /// Identifies the current user, setting [userProperties] and
  /// [userPropertiesSetOnce] on the person.
  ///
  /// - A new [distinctId] for an anonymous user sends `$identify`, linking
  ///   the anonymous history to the user, and reloads feature flags.
  /// - The current distinct id of an anonymous user marks it identified and
  ///   sends a `$set`; flags are reloaded only when properties were given.
  /// - The current distinct id of an identified user only sends the person
  ///   properties as a deduplicated `$set`, without reloading flags.
  /// - A different id while already identified is ignored: call [reset]
  ///   first to switch users.
  ///
  /// An empty [distinctId] is ignored, as are all calls while opted out or
  /// when `personProfiles` is `never`.
  void identify(
    String distinctId, {
    Map<String, Object?>? userProperties,
    Map<String, Object?>? userPropertiesSetOnce,
  }) {
    wrap(() {
      if (distinctId.trim().isEmpty) {
        logger.warn('identify was called with an empty distinct id. '
            'This call will be ignored.');
        return;
      }
      if (_ignoredWhileOptedOut('posthog.identify')) return;
      if (!_requirePersonProcessing('posthog.identify')) return;

      final previousDistinctId = getDistinctId();
      final isIdentified = _isIdentified();
      final identityChanged = distinctId != previousDistinctId;
      if (identityChanged && isIdentified) {
        logger.info('identify was called with "$distinctId", but the user is '
            'already identified as "$previousDistinctId". Call reset() '
            'before identifying another user. This call will be ignored.');
        return;
      }

      final hasUserProperties = (userProperties?.isNotEmpty ?? false) ||
          (userPropertiesSetOnce?.isNotEmpty ?? false);

      if (identityChanged) {
        setPersistedProperty(
            PostHogPersistedProperty.anonymousId, previousDistinctId);
        setPersistedProperty(PostHogPersistedProperty.distinctId, distinctId);
        setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
        _setPersonPropertiesForFlagsIfNeeded(
            userProperties, userPropertiesSetOnce);

        identifyStateless(
          distinctId,
          properties: _enrichProperties({
            'distinct_id': distinctId,
            r'$anon_distinct_id': previousDistinctId,
            ...maybeAdd(r'$set', userProperties),
            ...maybeAdd(r'$set_once', userPropertiesSetOnce),
          }),
        );
        if (userProperties != null || userPropertiesSetOnce != null) {
          _cachedPersonProperties = _personPropertiesHash(
              distinctId, userProperties, userPropertiesSetOnce);
        }
        _reloadFeatureFlags();
      } else if (!isIdentified) {
        // There is no anonymous history to link: the id already is the
        // anonymous one, so the transition is recorded with a $set.
        setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
        capture(r'$set', properties: {
          r'$set': userProperties ?? {},
          r'$set_once': userPropertiesSetOnce ?? {},
        });
        if (hasUserProperties) _reloadFeatureFlags();
      } else if (hasUserProperties) {
        // Person property changes are processed asynchronously by PostHog,
        // so reloading flags right away would not see them.
        setPersonProperties(
          userPropertiesToSet: userProperties,
          userPropertiesToSetOnce: userPropertiesSetOnce,
        );
      } else {
        logger.info('identify was called with the current distinct id of an '
            'identified user and no properties. This call will be ignored.');
      }
    });
  }

  /// Captures an event.
  ///
  /// `$set` / `$set_once` maps in [properties] update the person, and ask
  /// for person processing even for an anonymous user. `$groups` in
  /// [properties] apply to this event only; use [group] to associate the
  /// user with a group.
  void capture(String event, {Map<String, Object?>? properties}) {
    wrap(() {
      if (_ignoredWhileOptedOut('posthog.capture')) return;

      final userProperties = properties?[r'$set'];
      final userPropertiesSetOnce = properties?[r'$set_once'];
      if (_personProfiles != PostHogPersonProfiles.never &&
          (_isNonEmptyMap(userProperties) ||
              _isNonEmptyMap(userPropertiesSetOnce))) {
        _enablePersonProcessing();
      }
      _setPersonPropertiesForFlagsIfNeeded(
        _asPropertyMap(userProperties),
        _asPropertyMap(userPropertiesSetOnce),
      );

      final allProperties = _enrichProperties(properties);
      // Once an event is person-processed, all later ones are too.
      if (allProperties[r'$process_person_profile'] == true) {
        _enablePersonProcessing();
      }

      captureStateless(getDistinctId(), event, properties: allProperties);
      if (event == r'$set' || event == r'$identify') {
        final set = allProperties[r'$set'];
        final setOnce = allProperties[r'$set_once'];
        if (set is Map || setOnce is Map) {
          _cachedPersonProperties =
              _personPropertiesHash(getDistinctId(), set, setOnce);
        }
      }
    });
  }

  /// Creates an alias for a user. An empty [alias] is ignored.
  void alias(String alias) {
    wrap(() {
      if (alias.trim().isEmpty) {
        logger.warn('alias was called with an empty alias. '
            'This call will be ignored.');
        return;
      }
      if (_ignoredWhileOptedOut('posthog.alias')) return;
      if (!_requirePersonProcessing('posthog.alias')) return;

      aliasStateless(alias, getDistinctId(), properties: _enrichProperties({}));
    });
  }

  /// Adds group memberships to all later events, reloading feature flags
  /// when a group type moves to a different key.
  void _registerGroups(Map<String, Object> groups) {
    final existingGroups = _getGroups();

    register({
      r'$groups': {...existingGroups, ...groups},
    });

    if (groups.keys.any((type) => existingGroups[type] != groups[type])) {
      _reloadFeatureFlags();
    }
  }

  /// Associates the current user with a group for all later events, and
  /// sends a `$groupidentify` event with the optional [groupProperties].
  ///
  /// The group properties also feed feature flag evaluation. When the group
  /// key changes, the properties stored for the previous key are dropped and
  /// flags are reloaded. A call with an empty [groupType]
  /// or [groupKey] is ignored.
  void group(
    String groupType,
    String groupKey, {
    Map<String, Object?>? groupProperties,
  }) {
    wrap(() {
      if (groupType.trim().isEmpty || groupKey.trim().isEmpty) {
        logger.warn('group was called with an empty group type or key. '
            'This call will be ignored.');
        return;
      }
      if (_ignoredWhileOptedOut('posthog.group')) return;
      if (!_requirePersonProcessing('posthog.group')) return;

      if (_getGroups()[groupType] != groupKey) {
        resetGroupPropertiesForFlags(groupType: groupType);
      }
      // Stored before the group is registered, so the flags reload a new
      // group key triggers already evaluates with them.
      if (groupProperties != null && groupProperties.isNotEmpty) {
        setGroupPropertiesForFlags({groupType: groupProperties});
      }
      _registerGroups({groupType: groupKey});

      groupIdentifyStateless(
        groupType,
        groupKey,
        distinctId: getDistinctId(),
        eventProperties: _enrichProperties({}),
        groupProperties: groupProperties,
      );
    });
  }

  /// Person properties passed to identify() and capture() also feed flag
  /// evaluation. $set wins over $set_once for the same key.
  void _setPersonPropertiesForFlagsIfNeeded(
    Map<String, Object?>? userProperties,
    Map<String, Object?>? userPropertiesSetOnce,
  ) {
    final merged = <String, Object?>{
      ...?userPropertiesSetOnce,
      ...?userProperties,
    };
    if (merged.isEmpty) return;
    setPersonPropertiesForFlags(merged);
  }

  /// Sets person properties for feature flag evaluation, which the next
  /// flags reload sends.
  void setPersonPropertiesForFlags(Map<String, Object?> properties) {
    wrap(() {
      final existing = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties) ??
          {};
      setPersistedProperty(
        PostHogPersistedProperty.personProperties,
        {...existing, ...toJsonMap(properties, logger)},
      );
    });
  }

  /// Resets person properties for feature flag evaluation.
  void resetPersonPropertiesForFlags() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.personProperties, null);
    });
  }

  /// Sets group properties for feature flag evaluation. The /flags API
  /// accepts arbitrary JSON property values, so values are not forced to
  /// strings.
  void setGroupPropertiesForFlags(
      Map<String, Map<String, Object?>> properties) {
    wrap(() {
      final existing = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.groupProperties) ??
          {};

      final merged = <String, Object?>{...existing};
      for (final entry in properties.entries) {
        final current = merged[entry.key];
        merged[entry.key] = {
          if (current is Map)
            for (final e in current.entries) '${e.key}': e.value,
          ...toJsonMap(entry.value, logger),
        };
      }

      setPersistedProperty(PostHogPersistedProperty.groupProperties, merged);
    });
  }

  /// Resets the group properties for feature flag evaluation of
  /// [groupType], or of every group type when it is null.
  void resetGroupPropertiesForFlags({String? groupType}) {
    wrap(() {
      if (groupType == null) {
        setPersistedProperty(PostHogPersistedProperty.groupProperties, null);
        return;
      }
      final existing = getPersistedProperty<Map<String, Object?>>(
          PostHogPersistedProperty.groupProperties);
      if (existing == null || !existing.containsKey(groupType)) return;
      final remaining = {...existing}..remove(groupType);
      setPersistedProperty(PostHogPersistedProperty.groupProperties,
          remaining.isEmpty ? null : remaining);
    });
  }

  Future<void> _flagsAsync() {
    if (_loadingFlags) {
      logger.info('Feature flags are being loaded already, queuing reload.');
      // Reloads queued behind the one in flight share a single next request:
      // it sees every change made meanwhile, so it answers them all.
      return (_pendingFlagsReload ??= Completer<void>()).future;
    }
    return _doFlagsAsync();
  }

  Future<void> _doFlagsAsync() async {
    _loadingFlags = true;
    final generation = _featureFlagsGeneration;
    try {
      final distinctId = getDistinctId();
      final groupsMap = _getGroups();
      final personProperties = <String, Object?>{
        ...getDefaultPersonPropertiesForFlags(),
        ...getPersistedProperty<Map<String, Object?>>(
                PostHogPersistedProperty.personProperties) ??
            {},
      };
      final groupProperties = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.groupProperties) ??
          {};

      final timezone = getTimezone();
      final extraProperties = <String, Object?>{
        r'$anon_distinct_id': _getAnonymousId(),
        r'$device_id': _getDeviceId(),
        if (timezone != null) 'timezone': timezone,
      };

      final result = await getFlags(
        distinctId,
        groups: groupsMap,
        personProperties: personProperties,
        groupProperties: groupProperties.map((k, v) => MapEntry(
            k, v is Map ? Map<String, Object?>.from(v) : <String, Object?>{})),
        extraPayload: extraProperties,
      );

      if (generation != _featureFlagsGeneration) return;

      if (result is GetFlagsFailure) {
        final stored = _getStoredFlagDetails();
        _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
          flags: stored?.flags ?? {},
          requestError: result.error,
          // A failed request says nothing about the minimal events gate.
          minimalFlagCalledEvents: stored?.minimalFlagCalledEvents,
        ));
        return;
      }

      final res = (result as GetFlagsSuccess).response;
      // Set before the flags are stored: listeners notified by the store
      // may already read (and report) a flag.
      _flagsLoadedFromRemote = true;

      if (res.quotaLimited?.contains(QuotaLimitedFeature.featureFlags) ==
          true) {
        // Cached flags keep serving under the quota limit.
        final stored = _getStoredFlagDetails();
        _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
          flags: stored?.flags ?? {},
          requestId: stored?.requestId,
          evaluatedAt: stored?.evaluatedAt,
          errorsWhileComputingFlags: stored?.errorsWhileComputingFlags,
          quotaLimited: res.quotaLimited,
          minimalFlagCalledEvents: stored?.minimalFlagCalledEvents,
        ));
        logger.warn('[FEATURE FLAGS] Feature flags quota limit exceeded.');
        return;
      }

      var resolvedFlags = res.flags;
      if (res.errorsWhileComputingFlags) {
        final currentDetails = _getStoredFlagDetails();
        logger.info(
            'Cached feature flags: ', jsonEncode(currentDetails?.flags));

        final filteredFlags = <String, PostHogFeatureFlagDetail>{};
        for (final entry in res.flags.entries) {
          if (entry.value.failed != true) {
            filteredFlags[entry.key] = entry.value;
          }
        }

        resolvedFlags = {
          ...(currentDetails?.flags ?? {}),
          ...filteredFlags,
        };
      }

      // An empty response is stored too: it clears stale flags and any
      // previously recorded request error.
      _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
        flags: resolvedFlags,
        requestId: res.requestId,
        evaluatedAt: res.evaluatedAt,
        errorsWhileComputingFlags: res.errorsWhileComputingFlags,
        quotaLimited: res.quotaLimited,
        minimalFlagCalledEvents: res.minimalFlagCalledEvents,
      ));
    } finally {
      _loadingFlags = false;

      final pending = _pendingFlagsReload;
      if (pending != null) {
        _pendingFlagsReload = null;
        logger.info('Executing pending feature flags reload.');
        final next = wrap(_flagsAsync);
        pending.complete(next);
      }
    }
  }

  void _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat details) {
    wrap(() {
      setPersistedProperty(
          PostHogPersistedProperty.featureFlagDetails, details.toJson());
      _flagsRequestAnnounced = true;
      events.emit('featureflags',
          PostHogFlagsResponse(flags: details.flags).featureFlags);
    });
  }

  /// Announces the flags the client starts with, bootstrapped or cached by an
  /// earlier run, without waiting for `/flags`: once listeners can subscribe,
  /// after the constructor has returned, unless the outcome of a `/flags`
  /// request has been announced by then.
  void _announceStartupFlags() {
    if (_getStoredFlagDetails() == null) return;
    Timer.run(() => wrap(() {
          final flags = _getFeatureFlags();
          // Null once reset() has dropped them; its reload announces the next.
          if (_flagsRequestAnnounced || flags == null) return;
          events.emit('featureflags', flags);
        }));
  }

  /// Serves the enabled bootstrapped flags until the first complete `/flags`
  /// response. They replace any flags persisted by an earlier session.
  void _seedBootstrapFlags(PostHogBootstrapConfig bootstrap) {
    final bootstrapFlags = bootstrap.featureFlags;
    if (bootstrapFlags == null || bootstrapFlags.isEmpty) return;

    final flags = <String, PostHogFeatureFlagValue>{};
    for (final MapEntry(:key, :value) in bootstrapFlags.entries) {
      // Only enabled flags are served: false and '' are dropped.
      if (value == true || (value is String && value.isNotEmpty)) {
        flags[key] = value;
      } else if (value is! bool && value is! String) {
        logger.warn(
            'Ignoring bootstrapped feature flag "$key": expected a '
            'bool or a String, got',
            value.runtimeType);
      }
    }

    final payloads = <String, Object?>{};
    final details = <String, PostHogFeatureFlagDetail>{};
    for (final MapEntry(:key, :value) in flags.entries) {
      final payload = bootstrap.featureFlagPayloads?[key];
      String? encodedPayload;
      if (payload != null) {
        try {
          encodedPayload = jsonEncode(payload);
          payloads[key] = payload;
        } catch (e) {
          logger.warn(
              'Ignoring the bootstrapped payload of feature flag "$key":', e);
        }
      }
      details[key] = PostHogFeatureFlagDetail(
        key: key,
        enabled: true,
        variant: value is String ? value : null,
        metadata: encodedPayload != null
            ? PostHogFeatureFlagMetadata(payload: encodedPayload)
            : null,
      );
    }

    _bootstrappedFlags = flags;
    _bootstrappedPayloads = payloads;
    setPersistedProperty(PostHogPersistedProperty.featureFlagDetails,
        PostHogFlagsStorageFormat(flags: details).toJson());
  }

  // A persisted record of an unexpected shape must not turn every capture()
  // into a throw - the corrupted key is dropped instead.
  T? _discardingMalformed<T>(
      PostHogPersistedProperty key, T? Function() parse) {
    try {
      return parse();
    } catch (e) {
      logger.error('Discarding malformed persisted value for ${key.key}:', e);
      setPersistedProperty(key, null);
      return null;
    }
  }

  PostHogFlagsStorageFormat? _getStoredFlagDetails() {
    return _discardingMalformed(PostHogPersistedProperty.featureFlagDetails,
        () {
      final raw = getPersistedProperty<Map<String, Object?>>(
          PostHogPersistedProperty.featureFlagDetails);
      if (raw == null) return null;
      return PostHogFlagsStorageFormat.fromJson(raw,
          onMalformedFlag: (key, e) =>
              logger.warn('Skipping malformed feature flag "$key":', e));
    });
  }

  /// Gets the result for a specific feature flag, capturing
  /// `$feature_flag_called` when [sendEvent] is true.
  PostHogFeatureFlagResult? getFeatureFlagResult(
    String key, {
    required bool sendEvent,
  }) {
    final storedDetails = _getStoredFlagDetails();
    final details = storedDetails?.toResponse();
    final isQuotaLimited = storedDetails?.quotaLimited
            ?.contains(QuotaLimitedFeature.featureFlags) ==
        true;
    final featureFlag = details?.flags[key];
    final flagValue = getFeatureFlagValue(featureFlag);
    final shouldSendEvent = sendEvent &&
        !optedOut &&
        !(_flagCallReported[key]?.contains(flagValue) ?? false);

    if (shouldSendEvent) {
      final errors = <String>[];
      if (storedDetails?.requestError != null) {
        final reqError = storedDetails!.requestError!;
        switch (reqError.type) {
          case FeatureFlagRequestErrorType.timeout:
            errors.add(FeatureFlagErrorType.timeout.value);
          case FeatureFlagRequestErrorType.apiError:
            if (reqError.statusCode != null) {
              errors.add(FeatureFlagErrorType.apiError(reqError.statusCode!));
            }
          case FeatureFlagRequestErrorType.connectionError:
            errors.add(FeatureFlagErrorType.connectionError.value);
          case FeatureFlagRequestErrorType.unknownError:
            errors.add(FeatureFlagErrorType.unknownError.value);
        }
      } else if (storedDetails != null) {
        if (storedDetails.errorsWhileComputingFlags == true) {
          errors.add(FeatureFlagErrorType.errorsWhileComputing.value);
        }
        // A value answered from the cache is a valid answer: the quota state
        // is only an error when there is nothing to serve.
        if (flagValue == null) {
          if (isQuotaLimited) {
            errors.add(FeatureFlagErrorType.quotaLimited.value);
          } else if (featureFlag == null) {
            errors.add(FeatureFlagErrorType.flagMissing.value);
          }
        }
      }

      final featureFlagError = errors.isNotEmpty ? errors.join(',') : null;

      (_flagCallReported[key] ??= {}).add(flagValue);

      final bootstrappedValue = _bootstrappedFlags[key];
      final captureProperties = <String, Object?>{
        r'$feature_flag': key,
        r'$feature_flag_response': flagValue,
        ...maybeAdd(r'$feature_flag_id', featureFlag?.metadata?.id),
        ...maybeAdd(r'$feature_flag_version', featureFlag?.metadata?.version),
        ...maybeAdd(r'$feature_flag_reason',
            featureFlag?.reason?.description ?? featureFlag?.reason?.code),
        ...maybeAdd(r'$feature_flag_request_id', details?.requestId),
        ...maybeAdd(r'$feature_flag_evaluated_at', details?.evaluatedAt),
        ...maybeAdd(r'$feature_flag_error', featureFlagError),
        ...maybeAdd(r'$feature_flag_has_experiment',
            featureFlag?.metadata?.hasExperiment),
        if (bootstrappedValue != null) ...{
          r'$feature_flag_bootstrapped_response': bootstrappedValue,
          ...maybeAdd(r'$feature_flag_bootstrapped_payload',
              _bootstrappedPayloads[key]),
          r'$used_bootstrap_value': !_flagsLoadedFromRemote,
        },
      };

      capture(r'$feature_flag_called', properties: captureProperties);
    }

    if (flagValue == null) return null;

    // Payloads only accompany enabled flags.
    final rawPayload =
        featureFlag?.enabled == true ? featureFlag?.metadata?.payload : null;
    final payload = rawPayload != null
        ? parsePayload(rawPayload,
            onMalformed: (e) => logger.warn(
                'The payload of feature flag "$key" is not valid JSON, '
                'returning no payload:',
                e))
        : null;
    return PostHogFeatureFlagResult(
      key: key,
      enabled: flagValue is String ? true : flagValue as bool,
      variant: flagValue is String ? flagValue : null,
      payload: payload,
    );
  }

  /// Gets a feature flag value.
  ///
  /// Returns null if the flag does not exist or has not been loaded.
  PostHogFeatureFlagValue? getFeatureFlag(String key) {
    final result = getFeatureFlagResult(key, sendEvent: _sendFeatureFlagEvents);
    if (result == null) return null;
    return result.variant ?? result.enabled;
  }

  Map<String, PostHogFeatureFlagValue>? _getFeatureFlags() =>
      _getStoredFlagDetails()?.toResponse().featureFlags;

  /// Checks if a feature flag is enabled.
  bool? isFeatureEnabled(String key) {
    final response = getFeatureFlag(key);
    if (response == null) return null;
    if (response is bool) return response;
    return true; // String variants are truthy
  }

  void _reloadFeatureFlags() {
    wrap(() => _flagsAsync().catchError((Object e) {
          logger.info('Error reloading feature flags', e);
        }));
  }

  /// Reloads feature flags. Completes when they are loaded, or when the
  /// request failed; the failure is recorded for `$feature_flag_called`.
  Future<void> reloadFeatureFlagsAsync() async {
    await wrap(_flagsAsync);
  }

  /// Registers a callback for when feature flags are loaded. A callback
  /// registered right after the client is created also hears about the flags
  /// it starts with, bootstrapped or cached. Returns an unsubscribe function.
  void Function() onFeatureFlags(void Function() callback) =>
      events.on('featureflags', (_) => callback());

  bool _isIdentified() =>
      getPersistedProperty<String>(PostHogPersistedProperty.personMode) ==
      'identified';

  Map<String, String> _getGroups() {
    final groups = props[r'$groups'];
    if (groups is! Map) return {};
    return {
      for (final entry in groups.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  bool _hasPersonProcessing() {
    if (_personProfiles == PostHogPersonProfiles.always) return true;
    if (_personProfiles == PostHogPersonProfiles.never) return false;

    final isIdentified = _isIdentified();
    final hasGroups = _getGroups().isNotEmpty;
    final personProcessingEnabled = getPersistedProperty<bool>(
            PostHogPersistedProperty.enablePersonProcessing) ==
        true;

    return isIdentified || hasGroups || personProcessingEnabled;
  }

  bool _requirePersonProcessing(String functionName) {
    if (_personProfiles == PostHogPersonProfiles.never) {
      logger.error(
          '$functionName was called, but personProfiles is set to "never". This call will be ignored.');
      return false;
    }

    _enablePersonProcessing();
    return true;
  }

  void _enablePersonProcessing() {
    // capture() lands here for every person-processed event: the flag is
    // written only when it changes.
    if (getPersistedProperty<bool>(
            PostHogPersistedProperty.enablePersonProcessing) ==
        true) {
      return;
    }
    setPersistedProperty(PostHogPersistedProperty.enablePersonProcessing, true);
  }

  /// Event-producing calls do nothing while opted out: identity, groups and
  /// person properties must not change without the event that reports them.
  bool _ignoredWhileOptedOut(String functionName) {
    if (!optedOut) return false;
    logger.info(
        '$functionName was called while opted out. This call will be ignored.');
    return true;
  }

  /// Sets properties on the person profile. They also feed feature flag
  /// evaluation from the next flags reload on.
  void setPersonProperties({
    Map<String, Object?>? userPropertiesToSet,
    Map<String, Object?>? userPropertiesToSetOnce,
  }) {
    wrap(() {
      final isSetEmpty =
          userPropertiesToSet == null || userPropertiesToSet.isEmpty;
      final isSetOnceEmpty =
          userPropertiesToSetOnce == null || userPropertiesToSetOnce.isEmpty;
      if (isSetEmpty && isSetOnceEmpty) return;

      if (_ignoredWhileOptedOut('posthog.setPersonProperties')) return;
      if (!_requirePersonProcessing('posthog.setPersonProperties')) return;

      final hash = _personPropertiesHash(
          getDistinctId(), userPropertiesToSet, userPropertiesToSetOnce);

      if (_cachedPersonProperties == hash) {
        logger.info(
            'A duplicate setPersonProperties call was made. It has been ignored.');
        return;
      }

      final mergedProperties = {
        ...(userPropertiesToSetOnce ?? {}),
        ...(userPropertiesToSet ?? {}),
      };
      setPersonPropertiesForFlags(mergedProperties);

      capture(r'$set', properties: {
        r'$set': userPropertiesToSet ?? {},
        r'$set_once': userPropertiesToSetOnce ?? {},
      });
    });
  }

  static String _personPropertiesHash(
    String distinctId,
    Object? set,
    Object? setOnce,
  ) {
    Map<String, Object?>? asMap(Object? value) {
      if (value is! Map || value.isEmpty) return null;
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }

    return getPersonPropertiesHash(distinctId, asMap(set), asMap(setOnce));
  }

  static bool _isNonEmptyMap(Object? value) => value is Map && value.isNotEmpty;

  static Map<String, Object>? _asPropertyMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.value != null) entry.key.toString(): entry.value as Object,
    };
  }
}
