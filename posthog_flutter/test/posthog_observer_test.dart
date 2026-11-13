import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

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
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    fake.screenName = null;
    PosthogObserver.clearCurrentContext();
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
  });

  PosthogObserver getSut({
    ScreenNameExtractor nameExtractor = defaultNameExtractor,
    PostHogRouteFilter routeFilter = defaultPostHogRouteFilter,
  }) {
    return PosthogObserver(
      nameExtractor: nameExtractor,
      routeFilter: routeFilter,
    );
  }

  group('app language', () {
    setUp(() async {
      await Posthog().setAppLanguage(null);
      await Posthog().reportResolvedAppLanguage(null);
      fake.appLanguageCalls.clear();
    });

    Widget app(Locale locale, GlobalKey<NavigatorState> navigator) =>
        WidgetsApp(
          navigatorKey: navigator,
          color: const Color(0xFF000000),
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: const [
            DefaultWidgetsLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supported) => supported.firstWhere(
            (it) => it.languageCode == locale?.languageCode,
            orElse: () => supported.first,
          ),
          navigatorObservers: [getSut()],
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, __) => builder(context),
          ),
          home: const SizedBox(),
        );

    testWidgets('reports the locale the app resolved, not the requested one',
        (tester) async {
      await tester.pumpWidget(app(
        const Locale('fr', 'FR'),
        GlobalKey<NavigatorState>(),
      ));

      expect(fake.appLanguageCalls, ['en']);
    });

    testWidgets('picks up a language change on the next route', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(const Locale('en'), navigator));
      await tester.pumpWidget(app(const Locale('de'), navigator));
      await tester.pump();

      navigator.currentState!.push(route(const RouteSettings(name: 'next')));
      await tester.pumpAndSettle();

      expect(fake.appLanguageCalls, ['en', 'de']);
    });

    test('the value the app set wins over the resolved locale', () async {
      await Posthog().setAppLanguage(' pt_BR ');
      await Posthog().reportResolvedAppLanguage('en');
      await Posthog().setAppLanguage(null);

      expect(fake.appLanguageCalls, ['pt-BR', 'en']);
    });

    test('is sent again after setup', () async {
      await Posthog().setAppLanguage('de');
      await Posthog().setup(PostHogConfig('phc_test'));

      expect(fake.appLanguageCalls, ['de', 'de']);
    });
  });

  test('preserves WidgetsBindingObserver compatibility', () {
    expect(getSut(), isA<WidgetsBindingObserver>());
  });

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

  test('does not capture screen events when app is paused', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));

    final sut = getSut();

    // Simulate app going to background
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);

    sut.didPush(currentRoute, null);

    expect(fake.screenName, null);
  });

  test('does not capture screen events when app is inactive', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));

    final sut = getSut();

    // Simulate app becoming inactive
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    sut.didPush(currentRoute, null);

    expect(fake.screenName, null);
  });

  test('resumes capturing screen events when app returns to foreground', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));

    final sut = getSut();

    // Simulate app going to background and back
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    sut.didPush(currentRoute, null);
    expect(fake.screenName, null);

    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    sut.didPush(currentRoute, null);
    expect(fake.screenName, 'Current Route');
  });

  test('captures the previous route when popping in the foreground', () {
    final sut = getSut();
    sut.didPop(route(const RouteSettings(name: 'Current Route')),
        route(const RouteSettings(name: 'Previous Route')));
    expect(fake.screenName, 'Previous Route');
  });

  test('captures the new route when replacing in the foreground', () {
    final sut = getSut();
    sut.didReplace(
        newRoute: route(const RouteSettings(name: 'New Route')),
        oldRoute: route(const RouteSettings(name: 'Old Route')));
    expect(fake.screenName, 'New Route');
  });

  test('does not capture screen events on didPop when app is paused', () {
    final currentRoute = route(const RouteSettings(name: 'Current Route'));
    final previousRoute = route(const RouteSettings(name: 'Previous Route'));

    final sut = getSut();

    // Simulate app going to background
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);

    sut.didPop(currentRoute, previousRoute);

    expect(fake.screenName, null);
  });

  test('does not capture screen events on didReplace when app is paused', () {
    final oldRoute = route(const RouteSettings(name: 'Old Route'));
    final newRoute = route(const RouteSettings(name: 'New Route'));

    final sut = getSut();

    // Simulate app going to background
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);

    sut.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    expect(fake.screenName, null);
  });

  // Routers such as auto_route create an observer per nested navigator, and
  // nothing removes it from the binding when that navigator goes away.
  testWidgets(
      'does not stay registered with WidgetsBinding after its navigator is '
      'disposed', (tester) async {
    final observer = getSut();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          observers: [observer],
          onGenerateRoute: (_) => route(const RouteSettings(name: 'Home')),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    // removeObserver returns true only for an observer still registered.
    final wasRegistered = tester.binding.removeObserver(observer);
    expect(wasRegistered, isFalse);
  });
}

class CustomOverlawRoute extends OverlayRoute {
  CustomOverlawRoute({super.settings});

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    return [];
  }
}
