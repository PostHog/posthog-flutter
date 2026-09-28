import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/confirmation_message.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  PostHogDisplaySurvey completedSurvey({required bool displayThankYouMessage}) {
    return PostHogDisplaySurvey.fromDict({
      'id': 'survey-1',
      'name': 'Test survey',
      'questions': [
        {
          'type': 'open',
          'question': 'What can we do better?',
          'isOptional': false,
        },
      ],
      'appearance': {
        'displayThankYouMessage': displayThankYouMessage,
        'thankYouMessageHeader': 'Thanks so much',
      },
    });
  }

  Future<List<String>> pumpAndAnswer(WidgetTester tester, bool thankYou) async {
    final events = <String>[];
    final survey = completedSurvey(displayThankYouMessage: thankYou);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(Scaffold));
    unawaited(showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (context) => SurveyBottomSheet(
        survey: survey,
        appearance: SurveyAppearance.fromPostHog(survey.appearance),
        onShown: (_) => events.add('shown'),
        onResponse: (_, index, __) async {
          events.add('response:$index');
          return const PostHogSurveyNextQuestion(
            questionIndex: 0,
            isSurveyCompleted: true,
          );
        },
        onClosed: (_) => events.add('closed'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Faster checkout');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    return events;
  }

  testWidgets('shows the thank-you screen when displayThankYouMessage is true',
      (tester) async {
    final events = await pumpAndAnswer(tester, true);

    expect(find.byType(ConfirmationMessage), findsOneWidget);
    expect(find.text('Thanks so much'), findsOneWidget);
    expect(events, ['shown', 'response:0']);
  });

  testWidgets(
      'closes without a thank-you screen when displayThankYouMessage is false',
      (tester) async {
    final events = await pumpAndAnswer(tester, false);

    expect(find.byType(ConfirmationMessage), findsNothing);
    expect(find.text('Thanks so much'), findsNothing);
    expect(find.text('Thank you for your feedback!'), findsNothing);
    expect(events, ['shown', 'response:0', 'closed']);
  });
}
