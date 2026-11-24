import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

const linkQuestion = {
  'type': 'link',
  'question': 'Hi',
  'isOptional': false,
  'link': '',
};
const choiceQuestion = {
  'type': 'single_choice',
  'question': 'Pick one',
  'isOptional': false,
  'choices': ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'],
  'hasOpenChoice': true,
  'shuffleOptions': false,
};
const openQuestion = {
  'type': 'open',
  'question': 'Tell us more',
  'isOptional': false,
};

void main() {
  Future<void> showSurvey(
    WidgetTester tester, {
    String? position,
    Map<String, Object?> question = linkQuestion,
    void Function()? onClosed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [PosthogObserver()], home: Scaffold()),
    );
    SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict({
        'id': 'survey-1',
        'name': 'Test survey',
        'questions': [question],
        'appearance': {'position': position},
      }),
      (_) {},
      (_, __, ___) async => null,
      (_) => onClosed?.call(),
    );
    addTearDown(() async {
      SurveyService().hideSurvey();
      await tester.pumpAndSettle();
      PosthogObserver.clearCurrentContext();
    });
    await tester.pumpAndSettle();
  }

  void openKeyboard(WidgetTester tester, Size screen, double keyboard) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = screen
      ..padding = const FakeViewPadding(top: 59)
      ..viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
  }

  testWidgets('shows a top_center survey as a card at the top', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 120);
    addTearDown(tester.view.resetPadding);
    await showSurvey(tester, position: 'top_center');

    expect(find.byType(BottomSheet), findsNothing);
    final card = tester.getRect(find.byType(SurveyBottomSheet));
    expect(card.top, 120 / tester.view.devicePixelRatio + 16);
    expect(card.width, lessThanOrEqualTo(420));
    expect(tester.getRect(find.byType(IconButton)).top - card.top, 8);
  });

  for (final position in [null, 'center', 'unknown']) {
    testWidgets('keeps the bottom sheet for $position', (tester) async {
      await showSurvey(tester, position: position);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  }

  for (final position in ['left', 'right']) {
    testWidgets('pins a $position card to the bottom $position edge', (
      tester,
    ) async {
      await showSurvey(tester, position: position);
      final card = tester.getRect(find.byType(SurveyBottomSheet));
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(card.width, 420);
      expect(card.bottom, screen.height - 16);
      expect(position == 'left' ? card.left : screen.width - card.right, 16);
    });
  }

  testWidgets('closes a card with the close button', (tester) async {
    var closed = 0;
    await showSurvey(tester, position: 'right', onClosed: () => closed++);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.byType(SurveyBottomSheet), findsNothing);

    await showSurvey(tester, position: 'right');
    expect(find.byType(SurveyBottomSheet), findsOneWidget);
  });

  for (final question in [choiceQuestion, openQuestion]) {
    testWidgets('keeps ${question['type']} Submit above the keyboard', (
      tester,
    ) async {
      openKeyboard(tester, const Size(390, 844), 336);
      await showSurvey(tester, position: 'right', question: question);
      if (question == openQuestion) {
        await tester.enterText(find.byType(TextField), 'line\n' * 15);
        await tester.pumpAndSettle();
      }
      final card = tester.getRect(find.byType(SurveyBottomSheet));
      final submit = tester.getRect(find.text('Submit'));
      expect(submit.bottom, lessThanOrEqualTo(card.bottom));
      expect(submit.bottom, lessThanOrEqualTo(844 - 336));
    });

    testWidgets('lays out ${question['type']} in a short landscape card', (
      tester,
    ) async {
      openKeyboard(tester, const Size(844, 390), 200);
      await showSurvey(tester, position: 'right', question: question);
      expect(tester.takeException(), isNull);
    });
  }
}
