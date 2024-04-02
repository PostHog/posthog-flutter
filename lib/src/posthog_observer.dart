import 'package:flutter/widgets.dart';

import 'posthog.dart';

typedef ScreenNameExtractor = String? Function(RouteSettings settings);

String? defaultNameExtractor(RouteSettings settings) => settings.name;

class PosthogObserver extends RouteObserver<PageRoute<dynamic>> {
  PosthogObserver({ScreenNameExtractor nameExtractor = defaultNameExtractor})
      : _nameExtractor = nameExtractor;

  final ScreenNameExtractor _nameExtractor;

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

    _sendScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    _sendScreenView(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    _sendScreenView(previousRoute);
  }
}
