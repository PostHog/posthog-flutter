import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  PageRoute<dynamic> route(RouteSettings? settings) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => Container(),
        settings: settings,
      );

  final fake = PosthogFlutterPlatformFake();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PosthogFlutterPlatformInterface.instance = fake;
  });

  tearDown(() {
    fake.screenName = null;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
  });

  PosthogObserver getSut(
      {ScreenNameExtractor nameExtractor = defaultNameExtractor,
      PostHogRouteFilter routeFilter = defaultPostHogRouteFilter}) {
    return PosthogObserver(
        nameExtractor: nameExtractor, routeFilter: routeFilter);
  }

  test('returns current route name', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));

    final sut = getSut();
    sut.didPush(currentRoute, null);

    expect(fake.screenName, 'Current Route');
  });

  test('returns overriden route name', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));

    String? nameExtractor(RouteSettings settings) => 'overriden';

    final sut = getSut(nameExtractor: nameExtractor);
    sut.didPush(currentRoute, null);

    expect(fake.screenName, 'overriden');
  });

  test('returns overriden root route name', () {
    final currentRoute = route(const RouteSettings(name: '/'));

    final sut = getSut();
    sut.didPush(currentRoute, null);

    expect(fake.screenName, 'root (\'/\')');
  });

  test('does not capture not named routes', () {
    final currentRoute = route(const RouteSettings(name: null));

    final sut = getSut();
    sut.didPush(currentRoute, null);

    expect(fake.screenName, null);
  });

  test('does not capture blank routes', () {
    final currentRoute = route(const RouteSettings(name: '  '));

    final sut = getSut();
    sut.didPush(currentRoute, null);

    expect(fake.screenName, null);
  });

  test('does not capture filtered routes', () {
    // CustomOverlawRoute isn't a PageRoute
    final overlayRoute = CustomOverlawRoute(
      settings: const RouteSettings(name: 'Overlay Route'),
    );

    final sut = getSut();
    sut.didPush(overlayRoute, null);

    expect(fake.screenName, null);
  });

  test('allows overriding the route filter', () {
    final overlayRoute = CustomOverlawRoute(
      settings: const RouteSettings(name: 'Overlay Route'),
    );

    bool defaultPostHogRouteFilter(Route<dynamic>? route) =>
        route is PageRoute || route is OverlayRoute;

    final sut = getSut(routeFilter: defaultPostHogRouteFilter);
    sut.didPush(overlayRoute, null);

    expect(fake.screenName, 'Overlay Route');
  });
}

class CustomOverlawRoute extends OverlayRoute {
  CustomOverlawRoute({super.settings});

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return [];
  }
}
