enum Persistence {
  memory,
  file,
}

class PostHogSessionReplayConfig {
  /// Enable masking of all text input fields
  /// Experimental support
  /// Default: true
  final bool maskAllTextInputs;

  /// Enable masking of all images to a placeholder
  /// Experimental support
  /// Default: true
  final bool maskAllImages;

  /// Enable capturing of logcat as console events
  /// Android only
  /// Experimental support
  /// Default: true
  final bool captureLog;

  /// Debouncer delay used to reduce the number of snapshots captured and reduce performance impact
  /// This is used for capturing the view as a screenshot
  /// The lower the number, the more snapshots will be captured but higher the performance impact
  /// Defaults to 1s on iOS
  final Duration? iOSDebouncerDelay;

  /// Debouncer delay used to reduce the number of snapshots captured and reduce performance impact
  /// This is used for capturing the view as a screenshot
  /// The lower the number, the more snapshots will be captured but higher the performance impact
  /// Defaults to 0.5s on Android
  Duration? androidDebouncerDelay;

  /// Enable capturing network telemetry
  /// iOS only
  /// Experimental support
  /// Default: true
  final bool captureNetworkTelemetry;

  PostHogSessionReplayConfig({
    this.maskAllTextInputs = true,
    this.maskAllImages = true,
    this.captureLog = true,
    this.iOSDebouncerDelay,
    this.androidDebouncerDelay,
    this.captureNetworkTelemetry = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'maskAllTextInputs': maskAllTextInputs,
      'maskAllImages': maskAllImages,
      'captureLog': captureLog,
      'iOSDebouncerDelayMs': iOSDebouncerDelay?.inMilliseconds,
      'androidDebouncerDelayMs': androidDebouncerDelay?.inMilliseconds,
      'captureNetworkTelemetry': captureNetworkTelemetry,
    };
  }
}

class PostHogOptions {
  /// Allows you to provide the storage type. By default 'file'.
  /// 'file' will try to load the best available storage, the provided 'customStorage', 'customAsyncStorage' or in-memory storage.
  final Persistence persistence;

  /// Captures native app lifecycle events such as Application Installed, Application Updated, Application Opened, Application Became Active, and Application Backgrounded.
  /// By default is false.
  /// If you're already using the 'captureLifecycleEvents' options with 'withReactNativeNavigation' or 'PostHogProvider', you should not set this to true, otherwise you may see duplicated events.
  final bool captureNativeAppLifecycleEvents;

  /// Enable Recording of Session Replays for Android and iOS
  /// Requires 'Record user sessions' to be enabled in the PostHog Project Settings
  /// Experimental support
  /// Defaults to false
  final bool enableSessionReplay;

  /// Configuration for session replay
  final PostHogSessionReplayConfig? sessionReplayConfig;

  PostHogOptions({
    this.persistence = Persistence.file,
    this.captureNativeAppLifecycleEvents = false,
    this.enableSessionReplay = false,
    this.sessionReplayConfig,
  });

  Map<String, dynamic> toMap() {
    return {
      'persistence': persistence.toString().split('.').last,
      'captureNativeAppLifecycleEvents': captureNativeAppLifecycleEvents,
      'enableSessionReplay': enableSessionReplay,
      'sessionReplayConfig': sessionReplayConfig?.toMap(),
    };
  }
}
