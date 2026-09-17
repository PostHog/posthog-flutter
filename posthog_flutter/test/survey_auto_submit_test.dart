import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/rating_icons.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

Map<String, Object?> question(String type, {bool? skip, bool open = false}) => {
      'type': type == 'emoji' ? 'rating' : type,
      'question': 'First',
      'isOptional': false,
      if (skip != null) 'skipSubmitButton': skip,
      'ratingType': type == 'emoji' ? 1 : 0,
      'scaleLowerBound': 1,
      'scaleUpperBound': 5,
      'lowerBoundLabel': 'Low',
      'upperBoundLabel': 'High',
      'choices': ['A', 'B', if (open) 'Other'],
      'hasOpenChoice': open,
      'shuffleOptions': false,
    };

Future<void> showSurvey(WidgetTester tester,
    List<Map<String, Object?>> questions, OnSurveyResponse onResponse) async {
  final survey = PostHogDisplaySurvey.fromDict({
    'id': 'auto-submit',
    'name': 'Auto submit',
    'questions': questions,
  });
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SurveyBottomSheet(
    survey: survey,
    appearance: SurveyAppearance.fromPostHog(null),
    onShown: (_) {},
    onClosed: (_) {},
    onResponse: onResponse,
  ))));
}

void main() {
  for (final type in ['rating', 'emoji', 'single_choice']) {
    for (final skip in [true, false, null]) {
      testWidgets('$type submits on selection only when skip=$skip',
          (tester) => verifySubmission(tester, type, skip));
    }
  }

  for (final (type, open) in [
    ('single_choice', true),
    ('multiple_choice', false),
    ('multiple_choice', true),
  ]) {
    testWidgets('$type with open=$open keeps explicit submission',
        (tester) => verifyExplicitSubmission(tester, type, open));
  }

  testWidgets('pending response submits once and follows the native branch',
      (tester) async {
    final pending = Completer<PostHogSurveyNextQuestion>();
    final responses = <List<Object?>>[];
    await showSurvey(tester, [
      question('single_choice', skip: true),
      {...question('rating'), 'question': 'Skipped'},
      {...question('single_choice', skip: true), 'question': 'Next'},
    ], (_, index, response) {
      responses.add([index, response]);
      return index == 0
          ? pending.future
          : Future.value(const PostHogSurveyNextQuestion(
              questionIndex: 2, isSurveyCompleted: true));
    });
    await tester.tap(find.text('A'));
    await tester.tap(find.text('B'));
    expect(responses, hasLength(1));
    expect(responses.single, [
      0,
      ['A']
    ]);
    pending.complete(const PostHogSurveyNextQuestion(
        questionIndex: 2, isSurveyCompleted: false));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skipped'), findsNothing);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(responses.map((response) => response.first), [0, 2]);
    expect(responses.map((response) => response.last), [
      ['A'],
      ['B']
    ]);
  });

  testWidgets('closing while a response is pending does not update disposed UI',
      (tester) async {
    final pending = Completer<PostHogSurveyNextQuestion>();
    var calls = 0;
    await showSurvey(tester, [question('rating', skip: true)], (_, __, ___) {
      calls++;
      return pending.future;
    });
    await tester.tap(find.text('5'));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(const PostHogSurveyNextQuestion(
        questionIndex: 0, isSurveyCompleted: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> verifySubmission(
    WidgetTester tester, String type, bool? skip) async {
  final responses = <Object?>[];
  await showSurvey(tester, [question(type, skip: skip)],
      (_, index, response) async {
    expect(index, 0);
    responses.add(response);
    return const PostHogSurveyNextQuestion(
        questionIndex: 0, isSurveyCompleted: true);
  });
  expect(find.text('Submit'), skip == true ? findsNothing : findsOneWidget);
  await tester.tap(type == 'emoji'
      ? find.byType(RatingIcon).last
      : find.text(type == 'rating' ? '5' : 'B'));
  await tester.pumpAndSettle();
  if (skip != true) {
    expect(responses, isEmpty);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
  }
  expect(responses, [
    type == 'single_choice' ? ['B'] : 5
  ]);
  expect(find.text('First'), findsNothing);
}

Future<void> verifyExplicitSubmission(
    WidgetTester tester, String type, bool open) async {
  final responses = <Object?>[];
  await showSurvey(tester, [question(type, skip: true, open: open)],
      (_, index, response) async {
    responses.add(response);
    return const PostHogSurveyNextQuestion(
        questionIndex: 0, isSurveyCompleted: true);
  });
  await tester.tap(find.text('B'));
  await tester.pumpAndSettle();
  expect(responses, isEmpty);
  expect(find.text('Submit'), findsOneWidget);
  if (open) {
    await tester.tap(find.text('Other:'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Custom');
    await tester.pumpAndSettle();
    expect(responses, isEmpty);
  }
  await tester.tap(find.text('Submit'));
  await tester.pumpAndSettle();
  expect(responses, [
    [if (!open || type == 'multiple_choice') 'B', if (open) 'Custom']
  ]);
}
