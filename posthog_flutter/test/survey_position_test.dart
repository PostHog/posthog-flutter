import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  Future<void> showSurvey(WidgetTester tester, {String? position}) async {
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [PosthogObserver()], home: Scaffold()),
    );
    SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict({
        'id': 'survey-1',
        'name': 'Test survey',
        'questions': [
          {'type': 'link', 'question': 'Hi', 'isOptional': false, 'link': ''},
        ],
        'appearance': {'position': position},
      }),
      (_) {},
      (_, __, ___) async => null,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    SurveyService().hideSurvey();
    PosthogObserver.clearCurrentContext();
  });

  test('maps positions to card alignments, bottom center to the sheet', () {
    const expected = {
      'top_left': Alignment.topLeft,
      'top_center': Alignment.topCenter,
      'top_right': Alignment.topRight,
      'middle_left': Alignment.centerLeft,
      'middle_center': Alignment.center,
      'middle_right': Alignment.centerRight,
      'left': Alignment.bottomLeft,
      'right': Alignment.bottomRight,
      'center': null,
      'unknown': null,
      null: null,
    };
    expected.forEach((position, alignment) {
      expect(surveyCardAlignment(position), alignment, reason: '$position');
    });
  });

  testWidgets('shows a top_center survey as a card at the top', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 120, bottom: 60);
    addTearDown(tester.view.resetPadding);
    await showSurvey(tester, position: 'top_center');

    expect(find.byType(BottomSheet), findsNothing);
    final card = tester.getRect(find.byType(SurveyBottomSheet));
    // Status bar height (physical pixels) plus the card margin.
    expect(card.top, 120 / tester.view.devicePixelRatio + 16);
    expect(card.width, lessThanOrEqualTo(420));
    // System insets move the whole card, so the close button keeps its usual
    // 8px offset.
    expect(tester.getRect(find.byType(IconButton)).top - card.top, 8);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    expect(find.byType(SurveyBottomSheet), findsNothing);
  });

  testWidgets('keeps the bottom sheet without a position', (tester) async {
    await showSurvey(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
