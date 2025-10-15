import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  // // init WidgetsFlutterBinding if not yet

  WidgetsFlutterBinding.ensureInitialized();
  final config =
      PostHogConfig('phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D');
  config.debug = true;
  config.captureApplicationLifecycleEvents = false;
  config.host = 'https://us.i.posthog.com';
  config.surveys = true;
  config.sessionReplay = true;
  config.sessionReplayConfig.maskAllTexts = false;
  config.sessionReplayConfig.maskAllImages = false;
  config.sessionReplayConfig.throttleDelay = const Duration(milliseconds: 1000);
  config.flushAt = 1;
  await Posthog().setup(config);

  runApp(const MyApp());
}

/// This function runs in a separate isolate with its own sandboxed thread, meant to demonstate capturing exceptions from background "threads"
void _backgroundIsolateEntryPoint(SendPort sendPort) async {
  await Future.delayed(const Duration(milliseconds: 500));

  try {
    // Simulate an exception in the background isolate
    throw StateError('Background isolate processing failed!');
  } catch (e, stack) {
    // Send exception data back to main isolate for capture
    sendPort.send({
      'error': e.toString(),
      'errorType': e.runtimeType.toString(),
      'stackTrace': stack.toString(),
      'properties': {
        'test_type': 'background_isolate_exception',
        'isolate_name': 'exception-demo-worker',
        'button_pressed': 'capture_exception_background',
      },
    });
  }
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
                        if (mounted) {
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
                    "Error Tracking",
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

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Background isolate exception captured successfully! Check PostHog.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text("Capture Exception (Main)"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () async {
                    // Capture exception from background isolate
                    await _captureExceptionFromBackgroundIsolate();
                  },
                  child: const Text("Capture Exception (Background)"),
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

  /// Demonstrates exception capture from a background isolate
  /// This should show a different thread_id than the main isolate
  Future<void> _captureExceptionFromBackgroundIsolate() async {
    final receivePort = ReceivePort();

    // Spawn a background isolate with a custom name for demonstration
    await Isolate.spawn(
      _backgroundIsolateEntryPoint,
      receivePort.sendPort,
      debugName: 'custom-isolate-name-will-be-hashed-as-thread_id',
    );

    // Wait for the isolate to complete (or timeout after 5 seconds)
    final result = await receivePort.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => {'type': 'timeout'},
    );

    if (result is Map<String, dynamic>) {
      // Reconstruct the stack trace from the string
      final stackTrace = StackTrace.fromString(result['stackTrace']);

      // Create a synthetic error with the original error message and type
      final syntheticError =
          Exception('${result['errorType']}: ${result['error']}');

      await Posthog().captureException(
        error: syntheticError,
        stackTrace: stackTrace,
        properties: Map<String, Object>.from(result['properties'] ?? {}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Background isolate exception captured successfully! Check PostHog.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    receivePort.close();
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
