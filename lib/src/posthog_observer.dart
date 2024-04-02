import 'package:flutter/widgets.dart';

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

  final ScreenNameExtractor _nameExtractor;

  final PostHogRouteFilter _routeFilter;

  bool _isTrackeableRoute(String? name) {
    return name != null && name.trim().isNotEmpty;
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

      Posthog().screen(screenName: screenName!);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    if (!_routeFilter(route)) {
      return;
    }

    _sendScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    if (!_routeFilter(newRoute)) {
      return;
    }

    _sendScreenView(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    if (!_routeFilter(previousRoute)) {
      return;
    }

    _sendScreenView(previousRoute);
  }
}
