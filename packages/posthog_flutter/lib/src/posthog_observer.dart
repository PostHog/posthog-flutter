import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'posthog.dart';

typedef ScreenNameExtractor = String? Function(RouteSettings settings);

/// [PostHogRouteFilter] allows to filter out routes that should not be tracked.
///
/// By default, only [PageRoute]s are tracked.
typedef PostHogRouteFilter = bool Function(Route<dynamic>? route);

String? defaultNameExtractor(RouteSettings settings) => settings.name;

bool defaultPostHogRouteFilter(Route<dynamic>? route) => route is PageRoute;

class PosthogObserver extends RouteObserver<ModalRoute<dynamic>> {
  PosthogObserver(
      {ScreenNameExtractor nameExtractor = defaultNameExtractor,
      PostHogRouteFilter routeFilter = defaultPostHogRouteFilter})
      : _nameExtractor = nameExtractor,
        _routeFilter = routeFilter;

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
