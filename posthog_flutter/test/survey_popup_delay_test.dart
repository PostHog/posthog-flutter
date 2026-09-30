import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  Map<String, Object?> survey({Object? delaySeconds}) {
    return {
      'id': 'survey-1',
      'name': 'Test survey',
      'questions': [
        {
          'type': 'link',
          'question': 'Welcome',
          'isOptional': false,
          'link': '',
        },
      ],
      if (delaySeconds != null)
        'appearance': {'surveyPopupDelaySeconds': delaySeconds},
    };
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          observers: [PosthogObserver()],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    SurveyService().hideSurvey();
    PosthogObserver.clearCurrentContext();
  });

  testWidgets(
      'shows a survey immediately when the popup delay is unset or not positive',
      (
    tester,
  ) async {
    await pumpApp(tester);

    for (final delay in [null, 0, -1]) {
      final shown = SurveyService().showSurvey(
        PostHogDisplaySurvey.fromDict(survey(delaySeconds: delay)),
        (_) {},
        (_, __, ___) async => null,
        (_) {},
      );
      await tester.pump();

      expect(find.byType(SurveyBottomSheet), findsOneWidget);
      SurveyService().hideSurvey();
      await tester.pumpAndSettle();
      await shown;
    }
  });

  testWidgets('waits surveyPopupDelaySeconds before showing the survey', (
    tester,
  ) async {
    await pumpApp(tester);
    final closed = <String>[];

    final shown = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict(survey(delaySeconds: 2)),
      (_) {},
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    await tester.pump();

    expect(find.byType(SurveyBottomSheet), findsNothing);
    expect(closed, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(SurveyBottomSheet), findsOneWidget);
    expect(closed, isEmpty);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await shown;
  });

  testWidgets('does not show a survey hidden during its popup delay', (
    tester,
  ) async {
    await pumpApp(tester);
    final closed = <String>[];

    final shown = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict(survey(delaySeconds: 5)),
      (_) {},
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    await tester.pump();

    SurveyService().hideSurvey();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await shown;

    expect(find.byType(SurveyBottomSheet), findsNothing);
    expect(closed, ['survey-1']);
  });

  testWidgets('a later survey replaces one still waiting on its delay', (
    tester,
  ) async {
    await pumpApp(tester);
    final closed = <String>[];

    final first = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict({
        ...survey(delaySeconds: 10),
        'id': 'first',
      }),
      (_) {},
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    await tester.pump();

    final second = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict({
        ...survey(delaySeconds: 1),
        'id': 'second',
        'questions': [
          {
            'type': 'link',
            'question': 'Second',
            'isOptional': false,
            'link': '',
          },
        ],
      }),
      (_) {},
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);
    expect(closed, ['first']);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await first;
    await second;

    expect(find.byType(SurveyBottomSheet), findsNothing);
  });
}
