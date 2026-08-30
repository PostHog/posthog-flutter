import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  PostHogDisplaySurvey surveyWithIntro({
    required bool displayIntroScreen,
    String? header = 'Welcome!',
    String? description = 'Two quick questions.',
  }) {
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
        'displayIntroScreen': displayIntroScreen,
        if (header != null) 'introScreenHeader': header,
        if (description != null) 'introScreenDescription': description,
        'introScreenDescriptionContentType': 1,
        'introScreenButtonText': 'Get started',
      },
    });
  }

  // Presents the sheet the same way SurveyService does in production.
  Future<void> pumpSurveySheet(
    WidgetTester tester,
    PostHogDisplaySurvey survey,
    List<String> callbackLog,
  ) async {
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
        onShown: (_) => callbackLog.add('shown'),
        onResponse: (_, index, __) async {
          callbackLog.add('response:$index');
          return const PostHogSurveyNextQuestion(
            questionIndex: 0,
            isSurveyCompleted: true,
          );
        },
        onClosed: (_) => callbackLog.add('closed'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('SurveyBottomSheet intro screen', () {
    testWidgets(
        'shows the intro before the first question and advances without callbacks',
        (tester) async {
      final callbackLog = <String>[];
      await pumpSurveySheet(
          tester, surveyWithIntro(displayIntroScreen: true), callbackLog);

      // Intro visible, question not yet rendered
      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Two quick questions.'), findsOneWidget);
      expect(find.text('What can we do better?'), findsNothing);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      // Question 1 visible; advancing recorded no response and closed nothing
      expect(find.text('What can we do better?'), findsOneWidget);
      expect(find.text('Welcome!'), findsNothing);
      expect(callbackLog, ['shown']);
    });

    testWidgets('does not show the intro when displayIntroScreen is off',
        (tester) async {
      final callbackLog = <String>[];
      await pumpSurveySheet(
          tester, surveyWithIntro(displayIntroScreen: false), callbackLog);

      expect(find.text('Welcome!'), findsNothing);
      expect(find.text('What can we do better?'), findsOneWidget);
    });

    testWidgets(
        'skips the intro when it has neither a header nor a description',
        (tester) async {
      final callbackLog = <String>[];
      await pumpSurveySheet(
          tester,
          surveyWithIntro(
              displayIntroScreen: true, header: null, description: null),
          callbackLog);

      expect(find.text('Get started'), findsNothing);
      expect(find.text('What can we do better?'), findsOneWidget);
    });

    testWidgets('closing from the intro screen still notifies onClosed',
        (tester) async {
      final callbackLog = <String>[];
      await pumpSurveySheet(
          tester, surveyWithIntro(displayIntroScreen: true), callbackLog);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(callbackLog, ['shown', 'closed']);
    });
  });
}
