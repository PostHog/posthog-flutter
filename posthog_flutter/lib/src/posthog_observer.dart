import 'package:flutter/widgets.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

import 'posthog.dart';

/// Extracts a PostHog screen name from Flutter [RouteSettings].
///
/// Return `null` to skip tracking the route. The [settings] argument is the
/// route settings from the route being pushed, popped to, or replaced.
typedef ScreenNameExtractor = String? Function(RouteSettings settings);

/// Filters routes before [PosthogObserver] captures screen views.
///
/// Return `true` to allow tracking for [route] and `false` to ignore it. By
/// default, only [PageRoute]s are tracked.
typedef PostHogRouteFilter = bool Function(Route<dynamic>? route);

/// Returns [RouteSettings.name] as the screen name for [settings].
///
/// Returns `null` when the route settings do not define a name.
String? defaultNameExtractor(RouteSettings settings) => settings.name;

/// Returns whether [route] should be tracked by the default route filter.
///
/// The default implementation tracks only [PageRoute] instances.
bool defaultPostHogRouteFilter(Route<dynamic>? route) => route is PageRoute;

/// A Flutter [NavigatorObserver] that automatically captures `$screen` events.
///
/// Add this observer to `MaterialApp.navigatorObservers` or a router such as
/// `go_router` to capture screen views when named routes are pushed, popped, or
/// replaced.
class PosthogObserver extends RouteObserver<ModalRoute<dynamic>>
    with WidgetsBindingObserver {
  /// Creates a PostHog route observer.
  ///
  /// The [nameExtractor] reads a screen name from route settings. It defaults
  /// to [defaultNameExtractor], which returns [RouteSettings.name].
  ///
  /// The [routeFilter] determines which routes are eligible for tracking. It
  /// defaults to [defaultPostHogRouteFilter], which tracks [PageRoute]s.
  ///
  /// Screen events are only sent while the app is in the foreground.
  PosthogObserver({
    ScreenNameExtractor nameExtractor = defaultNameExtractor,
    PostHogRouteFilter routeFilter = defaultPostHogRouteFilter,
  })  : _nameExtractor = nameExtractor,
        _routeFilter = routeFilter {
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
  }

  AppLifecycleState? _appLifecycleState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  /// Whether the app is currently in the foreground (resumed state).
  /// Screen events are suppressed when the app is not in the foreground
  /// to avoid ghost screen views caused by background widget rebuilds.
  bool get _isAppInForeground {
    // If we haven't received a lifecycle state yet, assume foreground
    final state = _appLifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// The current navigation context, which can be used for showing modals
  /// This is updated whenever routes change (push, pop, replace)
  static BuildContext? _currentContext;

  /// For internal use only. Should not be used by app developers
  ///
  /// Returns the current context if it exists and is still mounted,
  /// otherwise returns null and clears the stored context.
  @internal
  static BuildContext? get currentContext {
    // From flutter docs: if a [BuildContext] is used across an asynchronous gap (i.e. after performing
    // an asynchronous operation), consider checking [mounted] to determine whether
    // the context is still valid before interacting with it:
    if (_currentContext?.mounted == false) {
      clearCurrentContext();
      return null;
    }
    return _currentContext;
  }

  /// Clears the current navigation context. Called when Posthog().close() is called.
  ///
  /// For internal use only. Should not be used by app developers.
  ///
  /// Note: Current limitation - After calling this method, PostHog will not have a valid BuildContext until
  /// the next navigation event occurs. This means if one calls `close()` followed by
  /// `setup()` on the same screen, surveys cannot be rendered until a navigation event occurs.
  @internal
  static void clearCurrentContext() {
    _currentContext = null;
  }

  final ScreenNameExtractor _nameExtractor;

  final PostHogRouteFilter _routeFilter;

  bool _isTrackeableRoute(String? name) {
    return name != null && name.trim().isNotEmpty;
  }

  /// Updates the current context from a route if available
  void _updateCurrentContext(Route<dynamic>? route) {
    final context = route?.navigator?.context;
    // don't clear current context if it's null
    if (context != null) {
      _currentContext = context;
    }
  }

  void _sendScreenView(Route<dynamic>? route) {
    if (route == null) {
      return;
    }

    if (!_isAppInForeground) {
      return;
    }

    var screenName = _nameExtractor(route.settings);
    if (_isTrackeableRoute(screenName)) {
      // if the screen name is the root route, we send it as root ("/") instead of only "/"
      if (screenName == '/') {
        screenName = 'root (\'/\')';
      }

      if (screenName == null) {
        return;
      }

      Posthog().screen(screenName: screenName);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    // Store the current context for use in showing surveys
    _updateCurrentContext(route);

    if (!_routeFilter(route)) {
      return;
    }

    _sendScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    // Update the current context when routes are replaced
    _updateCurrentContext(newRoute);

    if (!_routeFilter(newRoute)) {
      return;
    }

    _sendScreenView(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    // Update the current context when returning to a previous route
    _updateCurrentContext(previousRoute);

    if (!_routeFilter(previousRoute)) {
      return;
    }

    _sendScreenView(previousRoute);
  }
}
