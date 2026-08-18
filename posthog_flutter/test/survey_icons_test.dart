import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_choice_button.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_icon.dart';

void main() {
  testWidgets('selected choices draw the check without a font glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: Colors.white,
        builder: (_, __) => Center(
          child: SizedBox(
            width: 300,
            child: SurveyChoiceButton(
              label: 'Selected choice',
              isSelected: true,
              onTap: () {},
              appearance: SurveyAppearance.defaultAppearance,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    expect(
      tester.widget<SurveyIcon>(find.byType(SurveyIcon)).type,
      SurveyIconType.check,
    );
    expect(
      tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(SurveyIcon),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter,
      isA<SurveyIconPainter>(),
    );
  });

  testWidgets('survey sheet draws the close icon without a font glyph', (
    tester,
  ) async {
    final survey = PostHogDisplaySurvey.fromDict({
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
    });

    await tester.pumpWidget(
      WidgetsApp(
        color: Colors.white,
        builder: (_, __) => Material(
          child: SurveyBottomSheet(
            survey: survey,
            onShown: (_) {},
            onResponse: (_, __, ___) async => const PostHogSurveyNextQuestion(
              questionIndex: 0,
              isSurveyCompleted: true,
            ),
            onClosed: (_) {},
            appearance: SurveyAppearance.defaultAppearance,
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    expect(
      tester.widget<SurveyIcon>(find.byType(SurveyIcon)).type,
      SurveyIconType.close,
    );
  });
}
