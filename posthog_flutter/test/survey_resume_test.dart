import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  const channel = MethodChannel('posthog_flutter');
  final actions = <Map<dynamic, dynamic>>[];
  late PosthogFlutterIO platform;
  Future<Object?> Function(Map<dynamic, dynamic>)? respond;

  Map<String, Object?> survey({int? initialIndex}) => {
        'id': 'survey-1',
        'name': 'Feedback',
        'presentationId': 'attempt-2',
        if (initialIndex != null) 'initialQuestionIndex': initialIndex,
        'questions': [
          for (var index = 0; index < 3; index++)
            {
              'id': 'question-$index',
              'type': 'open',
              'question': 'Question $index',
              'isOptional': false,
            },
        ],
        'appearance': {
          'displayIntroScreen': true,
          'introScreenHeader': 'Welcome',
          'introScreenButtonText': 'Start',
          'displayThankYouMessage': true,
          'thankYouMessageHeader': 'Thanks',
        },
      };

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [PosthogObserver()],
      home: const Scaffold(body: Text('Home')),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    platform = PosthogFlutterIO();
    PosthogFlutterPlatformInterface.instance = platform;
    actions.clear();
    respond = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'surveyAction') return null;
      final args = call.arguments as Map;
      actions.add(args);
      if (args['type'] == 'response') {
        return respond != null
            ? respond!(args)
            : {'nextIndex': 2, 'isSurveyCompleted': true};
      }
      return null;
    });
  });

  tearDown(() {
    SurveyService().hideSurvey();
    PosthogObserver.clearCurrentContext();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'resumes at the native question and submits with its presentation',
      (tester) async {
    await mount(tester);
    final shown = platform.showSurvey(survey(initialIndex: 2));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsNothing);
    expect(find.text('Question 0'), findsNothing);
    expect(find.text('Question 1'), findsNothing);
    expect(find.text('Question 2'), findsOneWidget);
    expect(actions.single, {'type': 'shown', 'presentationId': 'attempt-2'});

    await tester.enterText(find.byType(TextField), 'Continue my response');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(actions.last, {
      'type': 'response',
      'presentationId': 'attempt-2',
      'index': 2,
      'response': 'Continue my response',
    });
    expect(find.text('Thanks'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await shown;
    expect(actions.last, {'type': 'closed', 'presentationId': 'attempt-2'});
  });

  testWidgets('fresh payloads still show the intro and start at question zero',
      (tester) async {
    await mount(tester);
    final shown = platform.showSurvey(survey());
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Question 0'), findsOneWidget);
    await platform.cleanupSurveys();
    await tester.pumpAndSettle();
    await shown;
    expect(actions.map((action) => action['type']), ['shown']);
  });

  testWidgets(
      'an invalidated native response hides without dismissing progress',
      (tester) async {
    respond = (_) async => null;
    await mount(tester);
    final shown = platform.showSurvey(survey(initialIndex: 2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Answer');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await shown;
    expect(tester.takeException(), isNull);
    expect(find.byType(SurveyBottomSheet), findsNothing);
    expect(actions.map((action) => action['type']), ['shown', 'response']);
  });

  testWidgets(
      'cleanup during a pending open answer does not update disposed UI',
      (tester) async {
    final response = Completer<Object?>();
    respond = (_) => response.future;
    await mount(tester);
    final shown = platform.showSurvey(survey(initialIndex: 2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Answer');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await platform.cleanupSurveys();
    await tester.pumpAndSettle();
    await shown;
    response.complete({'nextIndex': 2, 'isSurveyCompleted': true});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(actions.map((action) => action['type']), ['shown', 'response']);
  });
  testWidgets('a stale reply cannot hide a new survey presentation',
      (tester) async {
    final response = Completer<Object?>();
    respond = (_) => response.future;
    await mount(tester);
    final first = platform.showSurvey(survey(initialIndex: 2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Old answer');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await platform.cleanupSurveys();
    await tester.pumpAndSettle();
    await first;

    final next = platform.showSurvey({
      ...survey(initialIndex: 1),
      'presentationId': 'attempt-3',
    });
    await tester.pumpAndSettle();
    response.completeError(PlatformException(code: 'SurveyInvalidated'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Question 1'), findsOneWidget);
    expect(actions.map((action) => action['type']),
        ['shown', 'response', 'shown']);
    await platform.cleanupSurveys();
    await tester.pumpAndSettle();
    await next;
  });
}
