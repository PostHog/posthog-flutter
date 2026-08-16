import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
// This screen invokes the bridge directly to show a deterministic local survey.
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

class SurveyNestedNavigatorScreen extends StatelessWidget {
  const SurveyNestedNavigatorScreen({super.key});

  static const _survey = <String, dynamic>{
    'id': 'nested-navigator-test',
    'name': 'Nested navigator test',
    'questions': [
      {
        'id': 'feedback',
        'type': 'open',
        'question': 'Does this survey appear above the red shell?',
        'isOptional': false,
        'buttonText': 'Submit',
      },
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Navigator(
              observers: [PosthogObserver()],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'survey_nested_branch'),
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Nested navigator survey')),
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => PosthogFlutterPlatformInterface.instance
                          .showSurvey(_survey),
                      child: const Text('Show test survey'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 120,
              width: double.infinity,
              color: Colors.red,
              alignment: Alignment.center,
              child: const Text(
                'Persistent shell chrome',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
