import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  PostHogDisplaySurvey survey(String id) {
    return PostHogDisplaySurvey.fromDict({
      'id': id,
      'name': 'Test survey',
      'questions': [
        {'type': 'link', 'question': id, 'isOptional': false, 'link': ''},
      ],
    });
  }

  Future<void> pumpAppWithObserver(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PosthogObserver()],
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    SurveyService().hideSurvey();
    PosthogObserver.clearCurrentContext();
  });

  testWidgets('shows a survey that arrived before the observer had a context', (
    tester,
  ) async {
    final shown = <String>[];
    final closed = <String>[];

    final showSurvey = SurveyService().showSurvey(
      survey('early'),
      (survey) => shown.add(survey.id),
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    await tester.pump();
    expect(closed, isEmpty);

    await pumpAppWithObserver(tester);

    expect(find.byType(SurveyBottomSheet), findsOneWidget);
    expect(shown, ['early']);
    expect(closed, isEmpty);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await showSurvey;
  });

  testWidgets(
      'shows a waiting survey on the next navigation after the context was cleared',
      (
    tester,
  ) async {
    await pumpAppWithObserver(tester);
    PosthogObserver.clearCurrentContext();

    final showSurvey = SurveyService().showSurvey(
      survey('after-clear'),
      (_) {},
      (_, __, ___) async => null,
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(SurveyBottomSheet), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Next')),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byType(SurveyBottomSheet), findsOneWidget);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await showSurvey;
  });

  testWidgets('does not show a waiting survey that was hidden', (tester) async {
    final closed = <String>[];

    final showSurvey = SurveyService().showSurvey(
      survey('hidden'),
      (_) {},
      (_, __, ___) async => null,
      (survey) => closed.add(survey.id),
    );
    SurveyService().hideSurvey();
    await showSurvey;

    await pumpAppWithObserver(tester);

    expect(find.byType(SurveyBottomSheet), findsNothing);
    expect(closed, isEmpty);
  });

  testWidgets('a newer survey replaces one waiting for a context', (
    tester,
  ) async {
    final first = SurveyService().showSurvey(
      survey('first'),
      (_) {},
      (_, __, ___) async => null,
      (_) {},
    );
    final second = SurveyService().showSurvey(
      survey('second'),
      (_) {},
      (_, __, ___) async => null,
      (_) {},
    );
    await first;

    await pumpAppWithObserver(tester);

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await second;
  });
}
