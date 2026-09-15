import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_choice_button.dart';
import 'package:posthog_flutter/src/surveys/widgets/choice_question.dart';

void main() {
  for (final (isMultipleChoice, hasOpenChoice, shouldShuffle) in [
    (false, false, false),
    (false, false, true),
    (false, true, false),
    (false, true, true),
    (true, false, false),
    (true, false, true),
    (true, true, false),
    (true, true, true),
  ]) {
    testWidgets(
        'choice order and response: multiple=$isMultipleChoice, open=$hasOpenChoice, shuffle=$shouldShuffle',
        (tester) => verifyChoiceSubmission(
            tester, isMultipleChoice, hasOpenChoice, shouldShuffle));
  }

  testWidgets('choice-count updates preserve order and Other input',
      verifyChoiceCountUpdates);

  for (final choices in [
    <String>[],
    ['Other'],
    ['A', 'A', 'Other']
  ]) {
    testWidgets('renders every choice safely: $choices', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChoiceQuestionWidget(
        question: 'Pick one',
        description: null,
        choices: List.unmodifiable(choices),
        appearance: SurveyAppearance.fromPostHog(null),
        hasOpenChoice: true,
        shuffleOptions: true,
        onSubmit: (_) {},
      ))));
      final buttons = tester
          .widgetList<SurveyChoiceButton>(find.byType(SurveyChoiceButton))
          .toList();
      expect(buttons.map((button) => button.label).toList(), choices);
      expect(
          buttons
              .where((button) => button.isOpenChoice)
              .map((button) => button.label),
          choices.where((choice) => choice == 'Other'));
    });
  }
}

Future<void> verifyChoiceSubmission(WidgetTester tester, bool isMultipleChoice,
    bool hasOpenChoice, bool shouldShuffle) async {
  final choices = ['A', 'B', if (hasOpenChoice) 'Other'];
  final responses = <Object?>[];
  final survey = PostHogDisplaySurvey.fromDict({
    'id': 'shuffle',
    'name': 'Shuffle',
    'questions': [
      {
        'type': isMultipleChoice ? 'multiple_choice' : 'single_choice',
        'question': 'First',
        'choices': choices,
        'isOptional': false,
        'hasOpenChoice': hasOpenChoice,
        'shuffleOptions': shouldShuffle,
      },
      {
        'type': 'single_choice',
        'question': 'Next',
        'choices': ['Done'],
        'isOptional': false,
        'hasOpenChoice': false,
        'shuffleOptions': true,
      },
    ],
  });
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SurveyBottomSheet(
    survey: survey,
    appearance: SurveyAppearance.fromPostHog(survey.appearance),
    onShown: (_) {},
    onClosed: (_) {},
    onResponse: (_, index, response) async {
      expect(index, 0);
      responses.add(response);
      return const PostHogSurveyNextQuestion(
          questionIndex: 1, isSurveyCompleted: false);
    },
  ))));
  await tester.pumpAndSettle();
  List<String> visibleOrder() => tester
      .widgetList<SurveyChoiceButton>(find.byType(SurveyChoiceButton))
      .map((button) => button.label)
      .toList();
  final expectedOrder =
      shouldShuffle ? ['B', 'A', if (hasOpenChoice) 'Other'] : choices;
  expect(visibleOrder(), expectedOrder);
  expect(choices, ['A', 'B', if (hasOpenChoice) 'Other']);

  await tester.tap(find.text('B'));
  await tester.pumpAndSettle();
  expect(visibleOrder(), expectedOrder);
  if (hasOpenChoice) {
    await tester.tap(find.text('Other:'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Custom answer');
    await tester.pumpAndSettle();
    expect(visibleOrder(), expectedOrder);
  }
  await tester.tap(find.text('Submit'));
  await tester.pumpAndSettle();
  expect(responses, [
    hasOpenChoice ? [if (isMultipleChoice) 'B', 'Custom answer'] : ['B']
  ]);
  expect(find.text('Next'), findsOneWidget);
  expect(visibleOrder(), ['Done']);
}

Future<void> verifyChoiceCountUpdates(WidgetTester tester) async {
  Future<void> render(List<String> choices) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChoiceQuestionWidget(
          question: 'Pick one',
          description: null,
          choices: choices,
          appearance: SurveyAppearance.fromPostHog(null),
          hasOpenChoice: true,
          shuffleOptions: true,
          onSubmit: (_) {},
        )),
      ));
  List<String> visibleOrder() => tester
      .widgetList<SurveyChoiceButton>(find.byType(SurveyChoiceButton))
      .map((button) => button.label)
      .toList();
  await render(['A', 'B', 'Other']);
  expect(visibleOrder(), ['B', 'A', 'Other']);
  await tester.tap(find.text('Other:'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), 'Custom answer');
  await render(['A', 'B', 'C', 'Other']);
  await tester.pumpAndSettle();
  expect(visibleOrder(), ['B', 'A', 'C', 'Other']);
  expect(find.text('Custom answer'), findsOneWidget);
  expect(
      tester
          .widgetList<SurveyChoiceButton>(find.byType(SurveyChoiceButton))
          .last
          .isSelected,
      isTrue);
  await render(['A', 'Other']);
  await tester.pumpAndSettle();
  expect(visibleOrder(), ['A', 'Other']);
  expect(find.text('Custom answer'), findsOneWidget);
  await render([]);
  await tester.pumpAndSettle();
  expect(visibleOrder(), isEmpty);
}
