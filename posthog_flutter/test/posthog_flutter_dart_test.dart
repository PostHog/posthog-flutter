import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:posthog_flutter/posthog_flutter_dart.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_api_fake.dart';
import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  late Directory supportDirectory;
  late _PathProvider pathProvider;

  setUp(() {
    supportDirectory = Directory.systemTemp.createTempSync('posthog_plugin');
    final previousProvider = PathProviderPlatform.instance;
    pathProvider = _PathProvider(supportDirectory.path);
    PathProviderPlatform.instance = pathProvider;
    // Reading the default platform would construct the method-channel
    // implementation, which needs a Flutter binding.
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final previousPlatform = PosthogFlutterPlatformInterface.instance;
    addTearDown(() async {
      await PosthogFlutterPlatformInterface.instance.close();
      PosthogFlutterPlatformInterface.instance = previousPlatform;
      PathProviderPlatform.instance = previousProvider;
      supportDirectory.deleteSync(recursive: true);
    });
  });

  PostHogConfig configFor(LocalPostHogServer server) =>
      PostHogConfig('phc_test')
        ..host = server.url
        ..preloadFeatureFlags = false
        ..captureApplicationLifecycleEvents = false
        ..flushAt = 20;

  test('registerWith installs the implementation without resolving storage',
      () {
    PosthogFlutterDart.registerWith();
    expect(
        PosthogFlutterPlatformInterface.instance, isA<PosthogFlutterDesktop>());
    expect(pathProvider.lookups, 0);
  });

  test(
      'setup resolves application support storage and restores identity and queue',
      () async {
    final server = await LocalPostHogServer.start();
    PosthogFlutterDart.registerWith();
    var platform = PosthogFlutterPlatformInterface.instance;
    await platform.setup(configFor(server));
    expect(pathProvider.lookups, 1);
    final distinctId = await platform.getDistinctId();
    await platform.capture(eventName: 'persisted event');
    await platform.close();
    final sep = Platform.pathSeparator;
    expect(
        Directory('${supportDirectory.path}${sep}posthog${sep}phc_test')
            .existsSync(),
        isTrue);

    PosthogFlutterDart.registerWith();
    platform = PosthogFlutterPlatformInterface.instance;
    await platform.setup(configFor(server));
    expect(await platform.getDistinctId(), distinctId);
    await platform.capture(eventName: 'new event');
    await platform.flush();
    expect(server.eventNames, ['persisted event', 'new event']);
  });

  test('a new registration restores the persisted opt-out', () async {
    final server = await LocalPostHogServer.start();
    PosthogFlutterDart.registerWith();
    var platform = PosthogFlutterPlatformInterface.instance;
    await platform.setup(configFor(server));
    await platform.disable();
    await platform.close();

    PosthogFlutterDart.registerWith();
    platform = PosthogFlutterPlatformInterface.instance;
    await platform.setup(configFor(server));
    expect(await platform.isOptOut(), isTrue);
    await platform.capture(eventName: 'disabled event');
    await platform.flush();
    expect(server.events, isEmpty);
  });

  test('directory lookup failure leaves a working memory-only client',
      () async {
    final server = await LocalPostHogServer.start();
    pathProvider.fail = true;
    PosthogFlutterDart.registerWith();
    final platform = PosthogFlutterPlatformInterface.instance;
    await platform.setup(configFor(server));
    await platform.capture(eventName: 'memory event');
    await platform.flush();
    expect(server.eventNames, ['memory event']);
    expect(supportDirectory.listSync(), isEmpty);
  });
}

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.path);

  final String path;
  int lookups = 0;
  bool fail = false;

  @override
  Future<String?> getApplicationSupportPath() async {
    lookups++;
    if (fail) throw PlatformException(code: 'unavailable');
    return path;
  }
}
