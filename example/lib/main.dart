import 'package:flutter/material.dart';

import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  // // init WidgetsFlutterBinding if not yet
  // WidgetsFlutterBinding.ensureInitialized();
  // final config =
  //     PostHogConfig('phc_QFbR1y41s5sxnNTZoyKG2NJo2RlsCIWkUfdpawgb40D');
  // config.debug = true;
  // config.captureApplicationLifecycleEvents = true;
  // config.host = 'https://us.i.posthog.com';
  // await Posthog().setup(config);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _posthogFlutterPlugin = Posthog();
  dynamic _result = "";

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        // The PosthogObserver records screen views automatically
        PosthogObserver()
      ],
      home: Scaffold(
        appBar: AppBar(
          title: const Text('PostHog Flutter App'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                children: [
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                    child: const Text("distinctId"),
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
                    child: const Text("reloadFeatureFlags"),
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
      ),
    );
  }
}
