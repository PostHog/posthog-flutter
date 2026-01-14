import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  final config =
      PostHogConfig('phc_6lqCaCDCBEWdIGieihq5R2dZpPVbAUFISA75vFZow06');
  config.onFeatureFlags = () {
    debugPrint('[PostHog] Feature flags loaded!');
  };
  config.debug = true;
  config.captureApplicationLifecycleEvents = false;
  config.host = 'https://us.i.posthog.com';
  config.surveys = false;
  config.sessionReplay = false;
  config.sessionReplayConfig.maskAllTexts = false;
  config.sessionReplayConfig.maskAllImages = false;
  config.sessionReplayConfig.throttleDelay = const Duration(milliseconds: 1000);
  config.flushAt = 1;

  // Configure error tracking and exception capture
  config.errorTrackingConfig.captureFlutterErrors =
      true; // Capture Flutter framework errors
  config.errorTrackingConfig.capturePlatformDispatcherErrors =
      true; // Capture Dart runtime errors
  config.errorTrackingConfig.captureIsolateErrors =
      true; // Capture isolate errors

  if (kIsWeb) {
    runZonedGuarded(
      () => _initAndRun(config),
      (error, stackTrace) => _captureError(error, stackTrace),
    );
  } else {
    await _initAndRun(config);
  }
}

Future<void> _initAndRun(PostHogConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Posthog().setup(config);
  runApp(const MyApp());
}

Future<void> _captureError(Object error, StackTrace? stackTrace) async {
  final wrappedError = PostHogException(
      source: error, mechanism: 'runZonedGuarded', handled: false);
  await Posthog().captureException(error: wrappedError, stackTrace: stackTrace);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PostHogWidget(
      child: MaterialApp(
        navigatorObservers: [PosthogObserver()],
        title: 'Flutter App',
        home: const InitialScreen(),
      ),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({Key? key}) : super(key: key);

  @override
  InitialScreenState createState() => InitialScreenState();
}

class InitialScreenState extends State<InitialScreen> {
  final _posthogFlutterPlugin = Posthog();
  dynamic _result = "";

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PostHog Flutter App'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SecondRoute(),
                          settings: const RouteSettings(name: 'second_route')),
                    );
                  },
                  child: const PostHogMaskWidget(
                    child: Text(
                      'Go to Second Route',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Capture",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _posthogFlutterPlugin
                            .screen(screenName: "my screen", properties: {
                          "foo": "bar",
                        });
                      },
                      child: const Text("Capture Screen manually"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _posthogFlutterPlugin
                            .capture(eventName: "eventName", properties: {
                          "foo": "bar",
                        });
                      },
                      child: const Text("Capture Event"),
                    ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Activity",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () {
                        _posthogFlutterPlugin.disable();
                      },
                      child: const Text("Disable Capture"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        _posthogFlutterPlugin.enable();
                      },
                      child: const Text("Enable Capture"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () async {
                        final isOptedOut =
                            await _posthogFlutterPlugin.isOptOut();
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Opted out: $isOptedOut'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Check Opt-Out Status"),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.register("foo", "bar");
                  },
                  child: const Text("Register"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.unregister("foo");
                  },
                  child: const Text("Unregister"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.group(
                        groupType: "theType",
                        groupKey: "theKey",
                        groupProperties: {
                          "foo": "bar",
                        });
                  },
                  child: const Text("Group"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin
                        .identify(userId: "myId", userProperties: {
                      "foo": "bar",
                    }, userPropertiesSetOnce: {
                      "foo1": "bar1",
                    });
                  },
                  child: const Text("Identify"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.alias(alias: "myAlias");
                  },
                  child: const Text("Alias"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.debug(true);
                  },
                  child: const Text("Debug"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.reset();
                  },
                  child: const Text("Reset"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.flush();
                  },
                  child: const Text("Flush"),
                ),
                ElevatedButton(
                    onPressed: () async {
                      final result =
                          await _posthogFlutterPlugin.getDistinctId();
                      setState(() {
                        _result = result;
                      });
                    },
                    child: const PostHogMaskWidget(
                      child: Text("distinctId"),
                    )),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Error Tracking - Manual",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      // Simulate an exception in main isolate
                      // throw 'a custom error string';
                      // throw 333;
                      throw CustomException(
                        'This is a custom exception with additional context',
                        code: 'DEMO_ERROR_001',
                        additionalData: {
                          'user_action': 'button_press',
                          'timestamp': DateTime.now().millisecondsSinceEpoch,
                          'feature_enabled': true,
                        },
                      );
                    } catch (e, stack) {
                      await Posthog().captureException(
                        error: e,
                        stackTrace: stack,
                        properties: {
                          'test_type': 'main_isolate_exception',
                          'button_pressed': 'capture_exception_main',
                          'exception_category': 'custom',
                        },
                      );

                      if (mounted && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Main isolate exception captured successfully! Check PostHog.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text("Capture Exception"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () async {
                    await Posthog().captureException(
                      error: 'No Stack Trace Error',
                      properties: {'test_type': 'no_stack_trace'},
                    );
                  },
                  child: const Text("Capture Exception (Missing Stack)"),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Error Tracking - Autocapture",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Flutter error triggered! Check PostHog.'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }

                    // Test Flutter error handler by throwing in widget context
                    throw const CustomException(
                        'Test Flutter error for autocapture',
                        code: 'FlutterErrorTest',
                        additionalData: {'test_type': 'flutter_error'});
                  },
                  child: const Text("Test Flutter Error Handler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Test PlatformDispatcher error handler with Future
                    Future.delayed(Duration.zero, () {
                      // does not throw on web here, just with runZonedGuarded handler
                      throw const CustomException(
                          'Test PlatformDispatcher error for autocapture',
                          code: 'PlatformDispatcherTest',
                          additionalData: {
                            'test_type': 'platform_dispatcher_error'
                          });
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Dart runtime error triggered! Check PostHog.'),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const Text("Test Dart Error Handler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Test isolate error listener by throwing in an async callback
                    // does not throw on web here, just with runZonedGuarded handler
                    Timer(Duration.zero, () {
                      throw const CustomException(
                        'Isolate error for testing',
                        code: 'IsolateHandlerTest',
                        additionalData: {
                          'test_type': 'isolate_error_listener_timer',
                        },
                      );
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Isolate error triggered! Check PostHog.'),
                          backgroundColor: Colors.purple,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const Text("Test Isolate Error Handler"),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Feature flags",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _posthogFlutterPlugin
                        .getFeatureFlag("feature_name");
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const Text("Get Feature Flag status"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _posthogFlutterPlugin
                        .isFeatureEnabled("feature_name");
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const Text("isFeatureEnabled"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _posthogFlutterPlugin
                        .getFeatureFlagPayload("feature_name");
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const Text("getFeatureFlagPayload"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _posthogFlutterPlugin.reloadFeatureFlags();
                  },
                  child: const PostHogMaskWidget(
                      child: Text("reloadFeatureFlags")),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Data result",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(_result.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SecondRoute extends StatefulWidget {
  const SecondRoute({super.key});

  @override
  SecondRouteState createState() => SecondRouteState();
}

class SecondRouteState extends State<SecondRoute> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const PostHogMaskWidget(child: Text('First Route')),
      ),
      body: Center(
        child: RepaintBoundary(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: const PostHogMaskWidget(child: Text('Open route')),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ThirdRoute(),
                      settings: const RouteSettings(name: 'third_route'),
                    ),
                  ).then((_) {});
                },
              ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Sensitive Text Input',
                  hintText: 'Enter sensitive data',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              PostHogMaskWidget(
                  child: Image.asset(
                'assets/training_posthog.png',
                height: 200,
              )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class ThirdRoute extends StatelessWidget {
  const ThirdRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Third Route'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10.0,
            mainAxisSpacing: 10.0,
          ),
          itemCount: 16,
          itemBuilder: (context, index) {
            return Image.asset(
              'assets/posthog_logo.png',
              fit: BoxFit.cover,
            );
          },
        ),
      ),
    );
  }
}

/// Custom exception class for demonstration purposes
class CustomException implements Exception {
  final String message;
  final String? code;
  final Map<String, dynamic>? additionalData;

  const CustomException(
    this.message, {
    this.code,
    this.additionalData,
  });

  @override
  String toString() {
    if (code != null) {
      return 'CustomException($code): $message $additionalData';
    }
    return 'CustomException: $message $additionalData';
  }
}
