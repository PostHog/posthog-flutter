import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey_rating_type.dart';
import 'package:posthog_flutter/src/surveys/widgets/rating_icons.dart';
import 'package:posthog_flutter/src/surveys/widgets/rating_question.dart';

void main() {
  const scales = {
    2: [RatingIconType.thumbsUp, RatingIconType.thumbsDown],
    3: [
      RatingIconType.dissatisfied,
      RatingIconType.neutral,
      RatingIconType.satisfied
    ],
    5: [
      RatingIconType.veryDissatisfied,
      RatingIconType.dissatisfied,
      RatingIconType.neutral,
      RatingIconType.satisfied,
      RatingIconType.verySatisfied
    ],
  };
  for (final scale in scales.entries) {
    for (final lower in [0, 1]) {
      testWidgets(
          '${scale.key}-point emoji scale starting at $lower submits each value',
          (tester) async {
        final responses = <int>[];
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: RatingQuestion(
          question: 'Rate your experience',
          description: null,
          type: PostHogDisplaySurveyRatingType.emoji,
          scaleLowerBound: lower,
          scaleUpperBound: lower + scale.key - 1,
          onSubmit: responses.add,
        ))));
        final icons = find.byType(RatingIcon);
        expect(tester.widgetList<RatingIcon>(icons).map((icon) => icon.type),
            scale.value);
        await tester.tap(find.text('Submit'));
        expect(responses, isEmpty);
        for (var index = 0; index < scale.key; index++) {
          await tester.tap(icons.at(index));
          await tester.pumpAndSettle();
          expect(
              tester
                  .widgetList<RatingIcon>(icons)
                  .where((icon) => icon.selected),
              hasLength(1));
          expect(tester.widget<RatingIcon>(icons.at(index)).selected, isTrue);
          expect(responses, List.generate(index, (i) => lower + i));
          await tester.tap(find.text('Submit'));
          expect(responses, List.generate(index + 1, (i) => lower + i));
          await tester.tap(icons.at(index));
          await tester.pumpAndSettle();
          expect(
              tester.widgetList<RatingIcon>(icons).any((icon) => icon.selected),
              isFalse);
          await tester.tap(find.text('Submit'));
          expect(responses, List.generate(index + 1, (i) => lower + i));
        }
      });
    }
  }
}
