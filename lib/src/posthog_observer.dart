import 'package:flutter/widgets.dart';

import 'posthog.dart';

typedef ScreenNameExtractor = String? Function(RouteSettings settings);

String? defaultNameExtractor(RouteSettings settings) => settings.name;

class PosthogObserver extends RouteObserver<PageRoute<dynamic>> {
  PosthogObserver({ScreenNameExtractor nameExtractor = defaultNameExtractor})
      : _nameExtractor = nameExtractor;

  final ScreenNameExtractor _nameExtractor;

  void _sendScreenView(PageRoute<dynamic> route) {
    String? screenName = _nameExtractor(route.settings);
    if (screenName != null) {
      // if the screen name is the root route, we send it as root ("/") instead of only "/"
      if (screenName == '/') {
        screenName = 'root ("/")';
      }

      Posthog().screen(screenName: screenName);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _sendScreenView(route);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute) {
      _sendScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is PageRoute && route is PageRoute) {
      _sendScreenView(previousRoute);
    }
  }
}
