import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

Future<List<Object?>> pumpQuestion(
  WidgetTester tester,
  Map<String, Object?> question, {
  Map<String, Object?>? appearance,
}) async {
  final responses = <Object?>[];
  final survey = PostHogDisplaySurvey.fromDict({
    'id': 'optional-survey',
    'name': 'Optional',
    'questions': [question],
    if (appearance != null) 'appearance': appearance,
  });
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SurveyBottomSheet(
        survey: survey,
        appearance: SurveyAppearance.fromPostHog(survey.appearance),
        onShown: (_) {},
        onClosed: (_) {},
        onResponse: (_, index, response) async {
          responses.add(response);
          return PostHogSurveyNextQuestion(
            questionIndex: index,
            isSurveyCompleted: true,
          );
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return responses;
}

void main() {
  testWidgets('optional open text can be submitted empty with its button label',
      (tester) async {
    final responses = await pumpQuestion(tester, {
      'type': 'open',
      'question': 'Anything else?',
      'isOptional': true,
      'buttonText': 'Skip',
    });

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Skip'),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(responses, ['']);
  });

  testWidgets('optional rating can be submitted with no selection',
      (tester) async {
    final responses = await pumpQuestion(tester, {
      'type': 'rating',
      'question': 'How was it?',
      'isOptional': true,
      'buttonText': 'Next',
      'ratingType': 0,
      'scaleLowerBound': 1,
      'scaleUpperBound': 5,
      'lowerBoundLabel': 'Low',
      'upperBoundLabel': 'High',
    });

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Next'),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(responses, [null]);
  });

  testWidgets(
      'open text falls back when the question label is missing or blank',
      (tester) async {
    for (final buttonText in <Object?>[null, '', '   ']) {
      await pumpQuestion(tester, {
        'type': 'open',
        'question': 'Anything else?',
        'isOptional': true,
        if (buttonText != null) 'buttonText': buttonText,
      });

      expect(find.text('Submit'), findsOneWidget);
    }

    await pumpQuestion(
      tester,
      {
        'type': 'open',
        'question': 'Anything else?',
        'isOptional': true,
        'buttonText': '',
      },
      appearance: {'submitButtonText': 'Send'},
    );

    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);

    await pumpQuestion(tester, {
      'type': 'rating',
      'question': 'How was it?',
      'isOptional': true,
      'buttonText': '',
      'ratingType': 0,
      'scaleLowerBound': 1,
      'scaleUpperBound': 5,
      'lowerBoundLabel': 'Low',
      'upperBoundLabel': 'High',
    });
    expect(find.text('Submit'), findsOneWidget);
  });
}
