import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/widgets/open_text_question.dart';

void main() {
  final cases = <String, String?>{
    'unset': null,
    'empty': '',
    'configured': 'Tell us more',
  };

  for (final entry in cases.entries) {
    testWidgets('open-text placeholder is ${entry.key}', (tester) async {
      final survey = PostHogDisplaySurvey.fromDict({
        'id': 'survey-1',
        'name': 'Feedback',
        'questions': [
          {
            'type': 'open',
            'question': 'What can we improve?',
            'isOptional': false,
          },
        ],
        'appearance': {
          if (entry.value != null) 'placeholder': entry.value,
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenTextQuestion(
              question: 'What can we improve?',
              description: null,
              appearance: SurveyAppearance.fromPostHog(survey.appearance),
              onSubmit: (_) {},
            ),
          ),
        ),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        entry.value?.isNotEmpty == true ? entry.value : null,
      );
    });
  }
}
