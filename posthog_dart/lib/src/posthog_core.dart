import 'dart:async';
import 'dart:convert';

import 'feature_flag_utils.dart';
import 'posthog_core_stateless.dart';
import 'types.dart';
import 'utils/utils.dart';
import 'uuid.dart';

/// How to handle missing flags in `_getFeatureFlagResult`.
enum _MissingFlagBehavior { getFeatureFlag }

/// Options for async flag loading.
class _FlagsAsyncOptions {
  final bool sendAnonDistinctId;

  const _FlagsAsyncOptions({
    this.sendAnonDistinctId = true,
  });
}

class _PendingFlagsRequest extends _FlagsAsyncOptions {
  final Completer<PostHogFlagsResponse?> completer;

  _PendingFlagsRequest({
    required this.completer,
    super.sendAnonDistinctId,
  });
}

/// Stateful PostHog client with session management, identity, and feature flags.
///
/// This is the main class that applications interact with. It extends
/// [PostHogCoreStateless] with state management for sessions, identity,
/// feature flags, and person profiles.
///
/// Subclasses must implement [fetch], [getLibraryId], [getLibraryVersion],
/// and [getCustomUserAgent].
abstract class PostHogCore extends PostHogCoreStateless {
  // options
  final bool _sendFeatureFlagEvents;
  final Map<String, bool> _flagCallReported = {};
  final List<BeforeSendCallback>? _beforeSend;

  // internal
  Future<PostHogFlagsResponse?>? _flagsResponseFuture;
  final Duration _sessionExpiration;
  static const Duration _sessionMaxLength = Duration(hours: 24);
  Map<String, Object?> _sessionProps = {};

  _PendingFlagsRequest? _pendingFlagsRequest;

  // person profiles
  final PostHogPersonProfiles _personProfiles;

  // cache for person properties to avoid duplicate $set events
  String? _cachedPersonProperties;

  PostHogCore(
    super.apiKey, {
    PostHogConfig options = const PostHogConfig(),
    super.storage,
  })  : _sendFeatureFlagEvents = options.sendFeatureFlagEvents,
        _sessionExpiration = options.sessionExpiration,
        _personProfiles = options.personProfiles,
        _beforeSend = options.beforeSend,
        super(options: options) {
    _setupBootstrap(options);
  }

  void _setupBootstrap(PostHogConfig options) {
    final bootstrap = options.bootstrap;
    if (bootstrap == null) return;

    if (bootstrap.distinctId != null) {
      if (bootstrap.isIdentifiedId) {
        final distinctId =
            getPersistedProperty<String>(PostHogPersistedProperty.distinctId);
        if (distinctId == null) {
          setPersistedProperty(
              PostHogPersistedProperty.distinctId, bootstrap.distinctId);
          setPersistedProperty(
              PostHogPersistedProperty.personMode, 'identified');
        }
      } else {
        final anonymousId =
            getPersistedProperty<String>(PostHogPersistedProperty.anonymousId);
        if (anonymousId == null) {
          setPersistedProperty(
              PostHogPersistedProperty.anonymousId, bootstrap.distinctId);
        }
      }
    }

    final bootstrapFlags = bootstrap.flags;
    if (bootstrapFlags != null && bootstrapFlags.isNotEmpty) {
      final bootstrapResponse = PostHogFlagsResponse(flags: bootstrapFlags);
      _setBootstrappedFeatureFlagDetails(bootstrapResponse);

      final currentDetails = _getKnownFeatureFlagDetails();
      final newFlags = <String, FeatureFlagDetail>{
        ...bootstrapFlags,
        ...(currentDetails?.flags ?? {}),
      };

      _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(flags: newFlags));
    }
  }

  void _clearProps() {
    props = null;
    _sessionProps = {};
    _flagCallReported.clear();
  }

  @override
  void Function() on(String event, Function listener) {
    return events.on(event, listener);
  }

  /// Resets the PostHog state. Clears all persisted properties except the queue
  /// and any properties specified in [propertiesToKeep].
  void reset({List<PostHogPersistedProperty>? propertiesToKeep}) {
    wrap(() {
      final allKeep = [
        PostHogPersistedProperty.queue,
        ...(propertiesToKeep ?? []),
      ];

      _clearProps();
      _cachedPersonProperties = null;

      for (final prop in PostHogPersistedProperty.values) {
        if (!allKeep.contains(prop)) {
          setPersistedProperty(prop, null);
        }
      }

      reloadFeatureFlags();
    });
  }

  @override
  Map<String, Object?> getCommonEventProperties() {
    final featureFlags = _getFeatureFlags();

    final featureVariantProperties = <String, Object?>{};
    if (featureFlags != null) {
      for (final entry in featureFlags.entries) {
        featureVariantProperties['\$feature/${entry.key}'] = entry.value;
      }
    }

    return {
      ...maybeAdd(r'$active_feature_flags', featureFlags?.keys.toList()),
      ...featureVariantProperties,
      ...super.getCommonEventProperties(),
    };
  }

  Map<String, Object?> _enrichProperties(Map<String, Object?>? properties) {
    return {
      ...props,
      ..._sessionProps,
      ...(properties ?? {}),
      ...getCommonEventProperties(),
      r'$session_id': getSessionId(),
    };
  }

  /// Returns the current session ID.
  String getSessionId() {
    if (!isInitialized) return '';

    var sessionId =
        getPersistedProperty<String>(PostHogPersistedProperty.sessionId);
    final sessionLastTimestamp = getPersistedProperty<int>(
            PostHogPersistedProperty.sessionLastTimestamp) ??
        0;
    final sessionStartTimestamp = getPersistedProperty<int>(
            PostHogPersistedProperty.sessionStartTimestamp) ??
        0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessionLastDif = now - sessionLastTimestamp;
    final sessionStartDif = now - sessionStartTimestamp;

    if (sessionId == null ||
        sessionLastDif > _sessionExpiration.inMilliseconds ||
        sessionStartDif > _sessionMaxLength.inMilliseconds) {
      sessionId = generateUuidV7();
      setPersistedProperty(PostHogPersistedProperty.sessionId, sessionId);
      setPersistedProperty(PostHogPersistedProperty.sessionStartTimestamp, now);
    }
    setPersistedProperty(PostHogPersistedProperty.sessionLastTimestamp, now);

    return sessionId;
  }

  /// Resets the session ID.
  void resetSessionId() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.sessionId, null);
      setPersistedProperty(PostHogPersistedProperty.sessionLastTimestamp, null);
      setPersistedProperty(
          PostHogPersistedProperty.sessionStartTimestamp, null);
    });
  }

  /// Returns the current anonymous ID.
  String getAnonymousId() {
    if (!isInitialized) return '';

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
    if (!isInitialized) return '';
    return getPersistedProperty<String>(PostHogPersistedProperty.distinctId) ??
        getAnonymousId();
  }

  /// Register properties for the current session only.
  void registerForSession(Map<String, Object?> properties) {
    if (!isInitialized) return;
    _sessionProps = {..._sessionProps, ...properties};
  }

  /// Unregister a session property.
  void unregisterForSession(String property) {
    if (!isInitialized) return;
    _sessionProps.remove(property);
  }

  /// Identifies a user with a distinct ID and optional properties.
  void identify(String? distinctId,
      {Map<String, Object?>? properties, PostHogCaptureOptions? options}) {
    wrap(() {
      if (!_requirePersonProcessing('posthog.identify')) return;

      final previousDistinctId = getDistinctId();
      distinctId ??= previousDistinctId;

      if (properties != null && properties[r'$groups'] != null) {
        _setGroups(properties[r'$groups'] as Map<String, Object>);
      }

      final userPropsOnce =
          properties?.remove(r'$set_once') as Map<String, Object?>?;
      final userProps =
          (properties?.remove(r'$set') as Map<String, Object?>?) ?? properties;

      final allProperties = _enrichProperties({
        r'$anon_distinct_id': getAnonymousId(),
        ...maybeAdd(r'$set', userProps),
        ...maybeAdd(r'$set_once', userPropsOnce),
      });

      if (distinctId != previousDistinctId) {
        setPersistedProperty(
            PostHogPersistedProperty.anonymousId, previousDistinctId);
        setPersistedProperty(PostHogPersistedProperty.distinctId, distinctId);
        setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
        reloadFeatureFlags();

        identifyStateless(distinctId!,
            properties: allProperties, options: options);

        _cachedPersonProperties = getPersonPropertiesHash(
          distinctId!,
          userProps is Map<String, Object?> ? userProps : null,
          userPropsOnce,
        );
      } else if (userProps != null || userPropsOnce != null) {
        setPersonProperties(
          userPropertiesToSet:
              userProps is Map<String, Object?> ? userProps : null,
          userPropertiesToSetOnce: userPropsOnce,
        );
      }
    });
  }

  /// Captures an event.
  void capture(String event,
      {Map<String, Object?>? properties, PostHogCaptureOptions? options}) {
    wrap(() {
      final distinctId = getDistinctId();

      if (properties != null && properties[r'$groups'] != null) {
        _setGroups(properties[r'$groups'] as Map<String, Object>);
      }

      final allProperties = _enrichProperties(properties);

      final hasPersonProcessing = _hasPersonProcessing();
      allProperties[r'$process_person_profile'] = hasPersonProcessing;
      allProperties[r'$is_identified'] = _isIdentified();

      if (hasPersonProcessing) {
        _requirePersonProcessing('capture');
      }

      captureStateless(distinctId, event,
          properties: allProperties, options: options);
    });
  }

  /// Creates an alias for a user.
  void alias(String alias) {
    wrap(() {
      if (!_requirePersonProcessing('posthog.alias')) return;

      final distinctId = getDistinctId();
      final allProperties = _enrichProperties({});
      aliasStateless(alias, distinctId, properties: allProperties);
    });
  }

  /// Sets group memberships for the current user.
  void _setGroups(Map<String, Object> groupProps) {
    if (!_requirePersonProcessing('posthog.group')) return;

    final existingGroups = (props[r'$groups'] as Map<String, Object?>?) ?? {};

    register({
      r'$groups': {...existingGroups, ...groupProps},
    });

    if (groupProps.keys
        .any((type) => existingGroups[type] != groupProps[type])) {
      reloadFeatureFlags();
    }
  }

  /// Associates the current user with a group and optionally sets group properties.
  ///
  /// If [groupProperties] is provided, a `$groupidentify` event is sent.
  void group(
    String groupType,
    Object groupKey, {
    Map<String, Object?>? groupProperties,
    PostHogCaptureOptions? options,
  }) {
    wrap(() {
      _setGroups({groupType: groupKey});

      if (groupProperties != null) {
        if (!_requirePersonProcessing('posthog.group')) return;

        final distinctId = getDistinctId();
        final eventProperties = _enrichProperties({});
        groupIdentifyStateless(
          groupType,
          groupKey,
          groupProperties: groupProperties,
          options: options,
          distinctId: distinctId,
          eventProperties: eventProperties,
        );
      }
    });
  }

  /// Sets person properties for feature flag evaluation.
  void setPersonPropertiesForFlags(Map<String, Object?> properties,
      {bool reloadFlags = true}) {
    wrap(() {
      final existing = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties) ??
          {};
      setPersistedProperty(
        PostHogPersistedProperty.personProperties,
        {...existing, ...properties},
      );
      if (reloadFlags) reloadFeatureFlags();
    });
  }

  /// Resets person properties for feature flag evaluation.
  void resetPersonPropertiesForFlags() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.personProperties, null);
    });
  }

  /// Sets group properties for feature flag evaluation.
  void setGroupPropertiesForFlags(Map<String, Map<String, String>> properties) {
    wrap(() {
      final existing = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.groupProperties) ??
          {};

      for (final groupType in existing.keys) {
        if (properties.containsKey(groupType)) {
          existing[groupType] = {
            ...(existing[groupType] as Map<String, Object?>? ?? {}),
            ...properties[groupType]!,
          };
          properties.remove(groupType);
        }
      }

      setPersistedProperty(
        PostHogPersistedProperty.groupProperties,
        {...existing, ...properties},
      );
    });
  }

  /// Resets group properties for feature flag evaluation.
  void resetGroupPropertiesForFlags() {
    wrap(() {
      setPersistedProperty(PostHogPersistedProperty.groupProperties, null);
    });
  }

  Future<PostHogFlagsResponse?> _flagsAsync(
      [_FlagsAsyncOptions? options]) async {
    final sendAnonDistinctId = options?.sendAnonDistinctId ?? true;

    if (_flagsResponseFuture != null) {
      logger.info('Feature flags are being loaded already, queuing reload.');
      if (_pendingFlagsRequest != null) {
        _flagsResponseFuture!
            .then(_pendingFlagsRequest!.completer.complete)
            .catchError(_pendingFlagsRequest!.completer.completeError);
      }

      final completer = Completer<PostHogFlagsResponse?>();
      _pendingFlagsRequest = _PendingFlagsRequest(
        completer: completer,
        sendAnonDistinctId: sendAnonDistinctId,
      );
      return completer.future;
    }

    return _doFlagsAsync(_FlagsAsyncOptions(
      sendAnonDistinctId: sendAnonDistinctId,
    ));
  }

  Future<PostHogFlagsResponse?> _doFlagsAsync(
      _FlagsAsyncOptions options) async {
    final completer = Completer<PostHogFlagsResponse?>();
    _flagsResponseFuture = completer.future;

    try {
      final distinctId = getDistinctId();
      final groupsMap = (props[r'$groups'] as Map<String, Object?>?) ?? {};
      final personProperties = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties) ??
          {};
      final groupProperties = getPersistedProperty<Map<String, Object?>>(
              PostHogPersistedProperty.groupProperties) ??
          {};

      final extraProperties = <String, Object?>{
        if (options.sendAnonDistinctId) r'$anon_distinct_id': getAnonymousId(),
      };

      final result = await getFlags(
        distinctId,
        groups: groupsMap.cast<String, Object>(),
        personProperties: personProperties.cast<String, String>(),
        groupProperties: groupProperties
            .map((k, v) => MapEntry(k, (v as Map).cast<String, String>())),
        extraPayload: extraProperties,
      );

      if (result is GetFlagsFailure) {
        _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
          flags: _getKnownFeatureFlagDetails()?.flags ?? {},
          requestError: result.error,
        ));
        completer.complete(null);
        return null;
      }

      final res = (result as GetFlagsSuccess).response;

      if (res.quotaLimited?.contains(QuotaLimitedFeature.featureFlags) ==
          true) {
        _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
          flags: _getKnownFeatureFlagDetails()?.flags ?? {},
          quotaLimited: res.quotaLimited,
        ));
        logger.warn('[FEATURE FLAGS] Feature flags quota limit exceeded.');
        completer.complete(res);
        return res;
      }

      if (res.flags.isNotEmpty) {
        if (_sendFeatureFlagEvents) {
          _flagCallReported.clear();
        }

        var resolvedFlags = res.flags;
        if (res.errorsWhileComputingFlags) {
          final currentDetails = _getKnownFeatureFlagDetails();
          logger.info(
              'Cached feature flags: ', jsonEncode(currentDetails?.flags));

          final filteredFlags = <String, FeatureFlagDetail>{};
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

        _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat(
          flags: resolvedFlags,
          requestId: res.requestId,
          evaluatedAt: res.evaluatedAt,
          errorsWhileComputingFlags: res.errorsWhileComputingFlags,
          quotaLimited: res.quotaLimited,
        ));
        setPersistedProperty(
            PostHogPersistedProperty.flagsEndpointWasHit, true);
      }

      completer.complete(res);
      return res;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _flagsResponseFuture = null;

      final pending = _pendingFlagsRequest;
      if (pending != null) {
        _pendingFlagsRequest = null;
        logger.info('Executing pending feature flags reload.');
        _flagsAsync(_FlagsAsyncOptions(
          sendAnonDistinctId: pending.sendAnonDistinctId,
        ))
            .then(pending.completer.complete)
            .catchError(pending.completer.completeError);
      }
    }
  }

  /// Called when remote config has been loaded.
  /// Override in subclasses to react to remote config changes.
  void _setKnownFeatureFlagDetails(PostHogFlagsStorageFormat? details) {
    wrap(() {
      setPersistedProperty(
          PostHogPersistedProperty.featureFlagDetails, details?.toJson());

      final flagValues = details != null
          ? PostHogFlagsResponse(flags: details.flags).featureFlags
          : <String, FeatureFlagValue>{};
      events.emit('featureflags', flagValues);
    });
  }

  PostHogFlagsResponse? _getKnownFeatureFlagDetails() {
    final storedRaw = getPersistedProperty<Map<String, Object?>>(
        PostHogPersistedProperty.featureFlagDetails);
    if (storedRaw == null) return null;
    return parseFlagsResponse(storedRaw);
  }

  PostHogFlagsStorageFormat? _getStoredFlagDetails() {
    final raw = getPersistedProperty<Map<String, Object?>>(
        PostHogPersistedProperty.featureFlagDetails);
    if (raw == null) return null;
    return PostHogFlagsStorageFormat.fromJson(raw);
  }

  PostHogFlagsResponse? _getBootstrappedFeatureFlagDetails() {
    final raw = getPersistedProperty<Map<String, Object?>>(
        PostHogPersistedProperty.bootstrapFeatureFlagDetails);
    if (raw == null) return null;
    return parseFlagsResponse(raw);
  }

  void _setBootstrappedFeatureFlagDetails(PostHogFlagsResponse details) {
    setPersistedProperty(PostHogPersistedProperty.bootstrapFeatureFlagDetails, {
      'flags': details.flags.map((k, v) => MapEntry(k, v.toJson())),
      if (details.requestId != null) 'requestId': details.requestId,
    });
  }

  Map<String, FeatureFlagValue>? _getBootstrappedFeatureFlags() {
    return _getBootstrappedFeatureFlagDetails()?.featureFlags;
  }

  Map<String, Object?>? _getBootstrappedFeatureFlagPayloads() {
    return _getBootstrappedFeatureFlagDetails()?.featureFlagPayloads;
  }

  /// Gets the result for a specific feature flag.
  PostHogFeatureFlagResult? getFeatureFlagResult(String key,
      {PostHogFeatureFlagResultOptions? options}) {
    if (!isInitialized) return null;
    return _getFeatureFlagResult(key, sendEvent: options?.sendEvent);
  }

  PostHogFeatureFlagResult? _getFeatureFlagResult(
    String key, {
    bool? sendEvent,
    _MissingFlagBehavior? missingFlagBehavior,
  }) {
    final storedDetails = _getStoredFlagDetails();
    final details = getFeatureFlagDetails();
    final isQuotaLimited = storedDetails?.quotaLimited
            ?.contains(QuotaLimitedFeature.featureFlags) ==
        true;
    final featureFlag = details?.flags[key];
    final shouldSendEvent = (sendEvent ?? _sendFeatureFlagEvents) &&
        !(_flagCallReported[key] ?? false);
    final flagValue = getFeatureFlagValue(featureFlag);

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
        if (isQuotaLimited) {
          errors.add(FeatureFlagErrorType.quotaLimited.value);
        } else if (flagValue == null && featureFlag == null) {
          errors.add(FeatureFlagErrorType.flagMissing.value);
        }
      }

      final bootstrappedResponse = _getBootstrappedFeatureFlags()?[key];
      final bootstrappedPayload = _getBootstrappedFeatureFlagPayloads()?[key];
      final featureFlagError = errors.isNotEmpty ? errors.join(',') : null;

      _flagCallReported[key] = true;

      final captureProperties = <String, Object?>{
        r'$feature_flag': key,
        r'$feature_flag_response': flagValue,
        ...maybeAdd(r'$feature_flag_id', featureFlag?.metadata?.id),
        ...maybeAdd(r'$feature_flag_version', featureFlag?.metadata?.version),
        ...maybeAdd(r'$feature_flag_reason',
            featureFlag?.reason?.description ?? featureFlag?.reason?.code),
        ...maybeAdd(
            r'$feature_flag_bootstrapped_response', bootstrappedResponse),
        ...maybeAdd(r'$feature_flag_bootstrapped_payload', bootstrappedPayload),
        r'$used_bootstrap_value': !(getPersistedProperty<bool>(
                PostHogPersistedProperty.flagsEndpointWasHit) ??
            false),
        ...maybeAdd(r'$feature_flag_request_id', details?.requestId),
        ...maybeAdd(r'$feature_flag_evaluated_at', details?.evaluatedAt),
        ...maybeAdd(r'$feature_flag_error', featureFlagError),
      };

      capture(r'$feature_flag_called', properties: captureProperties);
    }

    if (flagValue == null) {
      switch (missingFlagBehavior) {
        case _MissingFlagBehavior.getFeatureFlag:
          return details != null && details.flags.isNotEmpty
              ? PostHogFeatureFlagResult(
                  key: key, enabled: false, payload: null)
              : null;
        case null:
          return null;
      }
    }

    final rawPayload = featureFlag?.metadata?.payload;
    final payload = rawPayload != null ? parsePayload(rawPayload) : null;
    return PostHogFeatureFlagResult(
      key: key,
      enabled: flagValue is String ? true : flagValue as bool,
      variant: flagValue is String ? flagValue : null,
      payload: payload,
    );
  }

  /// Gets a feature flag value.
  FeatureFlagValue? getFeatureFlag(String key) {
    if (!isInitialized) return null;
    final result = _getFeatureFlagResult(key,
        missingFlagBehavior: _MissingFlagBehavior.getFeatureFlag);
    if (result == null) return null;
    return (result.variant as Object?) ?? result.enabled;
  }

  Map<String, FeatureFlagValue>? _getFeatureFlags() {
    return getFeatureFlagDetails()?.featureFlags;
  }

  /// Gets full feature flag details including overrides.
  PostHogFlagsResponse? getFeatureFlagDetails() {
    if (!isInitialized) return null;
    var details = _getKnownFeatureFlagDetails();
    final overriddenFlags = getPersistedProperty<Map<String, Object?>>(
        PostHogPersistedProperty.overrideFeatureFlags);

    if (overriddenFlags == null) return details;

    final defaultFlags = <String, FeatureFlagDetail>{};
    final currentFlags = details?.flags ?? {};
    defaultFlags.addAll(currentFlags);

    for (final entry in overriddenFlags.entries) {
      if (entry.value == false || entry.value == null) {
        defaultFlags.remove(entry.key);
      } else {
        defaultFlags[entry.key] = updateFlagValue(
            defaultFlags[entry.key], entry.value as FeatureFlagValue);
      }
    }

    return PostHogFlagsResponse(
      flags: defaultFlags,
      requestId: details?.requestId,
      evaluatedAt: details?.evaluatedAt,
    );
  }

  /// Checks if a feature flag is enabled.
  bool? isFeatureEnabled(String key) {
    if (!isInitialized) return null;
    final response = getFeatureFlag(key);
    if (response == null) return null;
    if (response is bool) return response;
    return true; // String variants are truthy
  }

  /// Triggers a feature flags reload (fire and forget).
  void reloadFeatureFlags(
      {void Function(Object? error, Map<String, FeatureFlagValue>? flags)?
          callback}) {
    if (!isInitialized) return;
    _flagsAsync(const _FlagsAsyncOptions(sendAnonDistinctId: true)).then((res) {
      callback?.call(null, res?.featureFlags);
    }).catchError((Object e) {
      callback?.call(e, null);
      if (callback == null) {
        logger.info('Error reloading feature flags', e);
      }
    });
  }

  /// Reloads feature flags and returns the result.
  Future<Map<String, FeatureFlagValue>?> reloadFeatureFlagsAsync(
      {bool sendAnonDistinctId = true}) async {
    if (!isInitialized) return null;
    final res = await _flagsAsync(
        _FlagsAsyncOptions(sendAnonDistinctId: sendAnonDistinctId));
    return res?.featureFlags;
  }

  /// Registers a callback for feature flag changes.
  void Function() onFeatureFlags(
      void Function(Map<String, FeatureFlagValue> flags) callback) {
    if (!isInitialized) return () {};
    return on('featureflags', (Object? _) {
      final flags = _getFeatureFlags();
      if (flags != null) {
        callback(flags);
      }
    });
  }

  /// Registers a callback for a specific feature flag.
  void Function() onFeatureFlag(
      String key, void Function(FeatureFlagValue value) callback) {
    if (!isInitialized) return () {};
    return on('featureflags', (Object? _) {
      final flagResponse = getFeatureFlag(key);
      if (flagResponse != null) {
        callback(flagResponse);
      }
    });
  }

  /// Overrides feature flags locally.
  void overrideFeatureFlag(Map<String, FeatureFlagValue>? flags) {
    wrap(() {
      setPersistedProperty(
          PostHogPersistedProperty.overrideFeatureFlags, flags);
    });
  }

  bool _isIdentified() {
    final personMode =
        getPersistedProperty<String>(PostHogPersistedProperty.personMode);

    if (personMode == 'identified') return true;

    if (personMode == null) {
      final distinctId =
          getPersistedProperty<String>(PostHogPersistedProperty.distinctId);
      final anonymousId =
          getPersistedProperty<String>(PostHogPersistedProperty.anonymousId);
      if (distinctId != null &&
          anonymousId != null &&
          distinctId != anonymousId) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> _getGroups() {
    return (props[r'$groups'] as Map<String, Object?>?) ?? {};
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

    setPersistedProperty(PostHogPersistedProperty.enablePersonProcessing, true);
    return true;
  }

  /// Creates a person profile for the current user.
  void createPersonProfile() {
    if (!isInitialized) return;
    if (_hasPersonProcessing()) return;
    if (!_requirePersonProcessing('posthog.createPersonProfile')) return;
    capture(r'$set', properties: {r'$set': {}, r'$set_once': {}});
  }

  /// Sets properties on the person profile.
  void setPersonProperties({
    Map<String, Object?>? userPropertiesToSet,
    Map<String, Object?>? userPropertiesToSetOnce,
    bool reloadFlags = true,
  }) {
    wrap(() {
      final isSetEmpty =
          userPropertiesToSet == null || userPropertiesToSet.isEmpty;
      final isSetOnceEmpty =
          userPropertiesToSetOnce == null || userPropertiesToSetOnce.isEmpty;
      if (isSetEmpty && isSetOnceEmpty) return;

      if (!_requirePersonProcessing('posthog.setPersonProperties')) return;

      final hash = getPersonPropertiesHash(
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
      setPersonPropertiesForFlags(mergedProperties, reloadFlags: reloadFlags);

      capture(r'$set', properties: {
        r'$set': userPropertiesToSet ?? {},
        r'$set_once': userPropertiesToSetOnce ?? {},
      });

      _cachedPersonProperties = hash;
    });
  }

  /// Override processBeforeEnqueue to run before_send hooks.
  @override
  FutureOr<Map<String, Object?>?> processBeforeEnqueue(
      Map<String, Object?> message) {
    if (_beforeSend == null || _beforeSend.isEmpty) return message;

    final props = (message['properties'] as Map<String, Object?>?) ?? {};
    final timestamp = message['timestamp'];
    final event = PostHogEvent(
      uuid: message['uuid'] as String,
      event: message['event'] as String,
      properties: Map<String, Object?>.from(props),
      userProperties: props[r'$set'] as Map<String, Object?>?,
      userPropertiesSetOnce: props[r'$set_once'] as Map<String, Object?>?,
      timestamp: timestamp is String ? DateTime.parse(timestamp) : null,
    );

    final beforeSendResult = _runBeforeSend(event);
    if (beforeSendResult is Future<PostHogEvent?>) {
      return beforeSendResult
          .then((result) => _applyBeforeSendResult(result, message, props));
    }
    return _applyBeforeSendResult(beforeSendResult, message, props);
  }

  Map<String, Object?>? _applyBeforeSendResult(PostHogEvent? result,
      Map<String, Object?> message, Map<String, Object?> props) {
    if (result == null) return null;

    final resultProps = <String, Object?>{
      ...(result.properties ?? props),
    };
    if (result.userProperties != null) {
      resultProps[r'$set'] = result.userProperties;
    } else {
      resultProps.remove(r'$set');
    }
    if (result.userPropertiesSetOnce != null) {
      resultProps[r'$set_once'] = result.userPropertiesSetOnce;
    } else {
      resultProps.remove(r'$set_once');
    }

    return {
      ...message,
      'uuid': result.uuid,
      'event': result.event,
      'properties': resultProps,
      'timestamp': result.timestamp.toUtc().toIso8601String(),
    };
  }

  FutureOr<PostHogEvent?> _runBeforeSend(PostHogEvent event) {
    if (_beforeSend == null) return event;

    PostHogEvent? result = event;
    bool hasAsync = false;

    // Check if any callback returns a Future
    for (final fn in _beforeSend) {
      try {
        final fnResult = fn(result!);
        if (fnResult is Future<PostHogEvent?>) {
          hasAsync = true;
          break;
        }
        result = fnResult;
        if (result == null) {
          logger.info(
              "Event '${event.event}' was rejected in beforeSend callback");
          return null;
        }
      } catch (e) {
        logger.error(
            "Error in beforeSend callback for event '${event.event}':", e);
      }
    }

    if (!hasAsync) return result;

    // Re-run with async handling
    return _runBeforeSendAsync(event);
  }

  Future<PostHogEvent?> _runBeforeSendAsync(PostHogEvent event) async {
    PostHogEvent? result = event;
    for (final fn in _beforeSend!) {
      try {
        final fnResult = fn(result!);
        result = fnResult is Future<PostHogEvent?> ? await fnResult : fnResult;
        if (result == null) {
          logger.info(
              "Event '${event.event}' was rejected in beforeSend callback");
          return null;
        }
      } catch (e) {
        logger.error(
            "Error in beforeSend callback for event '${event.event}':", e);
      }
    }
    return result;
  }
}
