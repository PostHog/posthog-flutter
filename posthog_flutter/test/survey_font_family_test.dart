import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_callbacks.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  // Not Roboto: the default Android test typography already uses Roboto, so it
  // would pass without the survey font being applied.
  const customFont = 'Lobster';

  PostHogDisplaySurvey openQuestionSurvey({
    Map<String, Object?> appearance = const {},
  }) {
    return PostHogDisplaySurvey.fromDict({
      'id': 'survey-1',
      'name': 'Test survey',
      'questions': [
        {
          'type': 'open',
          'question': 'What can we do better?',
          'questionDescription': 'Be honest.',
          'isOptional': false,
          'buttonText': 'Send',
        },
      ],
      'appearance': {'placeholder': 'Type here', ...appearance},
    });
  }

  Future<void> pumpSurveySheet(
    WidgetTester tester,
    PostHogDisplaySurvey survey,
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
        onShown: (_) {},
        onResponse: (_, __, ___) async => const PostHogSurveyNextQuestion(
          questionIndex: 0,
          isSurveyCompleted: true,
        ),
        onClosed: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  // The font family the text is actually laid out with, after inheritance.
  String? renderedFontFamily(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    return paragraph.text.style?.fontFamily;
  }

  String? inputFontFamily(WidgetTester tester) {
    return tester
        .widget<EditableText>(find.byType(EditableText))
        .style
        .fontFamily;
  }

  group('surveyFontFamily', () {
    test('keeps a font family, trimmed', () {
      expect(surveyFontFamily(customFont), customFont);
      expect(surveyFontFamily('  $customFont '), customFont);
    });

    test('treats null, blank and inherit as the default font', () {
      expect(surveyFontFamily(null), isNull);
      expect(surveyFontFamily(''), isNull);
      expect(surveyFontFamily('   '), isNull);
      expect(surveyFontFamily('inherit'), isNull);
      expect(surveyFontFamily('Inherit'), isNull);
    });

    test('is applied by SurveyAppearance.fromPostHog', () {
      expect(
        SurveyAppearance.fromPostHog(
          const PostHogDisplaySurveyAppearance(fontFamily: customFont),
        ).fontFamily,
        customFont,
      );
      expect(
        SurveyAppearance.fromPostHog(
          const PostHogDisplaySurveyAppearance(fontFamily: 'inherit'),
        ).fontFamily,
        isNull,
      );
      expect(SurveyAppearance.fromPostHog(null).fontFamily, isNull);
    });
  });

  group('SurveyBottomSheet fontFamily', () {
    testWidgets('applies the font to question, description, button and input',
        (tester) async {
      await pumpSurveySheet(
        tester,
        openQuestionSurvey(appearance: {'fontFamily': customFont}),
      );

      expect(renderedFontFamily(tester, 'What can we do better?'), customFont);
      expect(renderedFontFamily(tester, 'Be honest.'), customFont);
      expect(renderedFontFamily(tester, 'Send'), customFont);
      expect(renderedFontFamily(tester, 'Type here'), customFont);
      expect(inputFontFamily(tester), customFont);
    });

    testWidgets('keeps the explicit text styles of the survey widgets',
        (tester) async {
      await pumpSurveySheet(
        tester,
        openQuestionSurvey(appearance: {'fontFamily': customFont}),
      );

      final question = tester
          .renderObject<RenderParagraph>(find.descendant(
            of: find.text('What can we do better?'),
            matching: find.byType(RichText),
          ))
          .text
          .style!;
      expect(question.fontSize, 18);
      expect(question.fontWeight, FontWeight.bold);
    });

    testWidgets('applies the font to the intro screen', (tester) async {
      await pumpSurveySheet(
        tester,
        openQuestionSurvey(appearance: {
          'fontFamily': customFont,
          'displayIntroScreen': true,
          'introScreenHeader': 'Welcome!',
          'introScreenButtonText': 'Get started',
        }),
      );

      expect(renderedFontFamily(tester, 'Welcome!'), customFont);
      expect(renderedFontFamily(tester, 'Get started'), customFont);
    });

    for (final fontFamily in [null, '', 'inherit']) {
      testWidgets('uses the default font when fontFamily is "$fontFamily"',
          (tester) async {
        await pumpSurveySheet(
          tester,
          openQuestionSurvey(appearance: {'fontFamily': fontFamily}),
        );

        final theme = Theme.of(tester.element(find.byType(Scaffold)));
        // The sheet's Material sets DefaultTextStyle from bodyMedium.
        expect(
          renderedFontFamily(tester, 'What can we do better?'),
          theme.textTheme.bodyMedium?.fontFamily,
        );
        expect(
          renderedFontFamily(tester, 'Send'),
          theme.textTheme.labelLarge?.fontFamily,
        );
        expect(inputFontFamily(tester), theme.textTheme.bodyLarge?.fontFamily);
      });
    }

    testWidgets('renders without errors when the font is not bundled',
        (tester) async {
      // Flutter falls back to the default font for an unknown family, so the
      // family is passed through as-is and nothing throws.
      await pumpSurveySheet(
        tester,
        openQuestionSurvey(appearance: {'fontFamily': 'NotBundledFont'}),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('What can we do better?'), findsOneWidget);
      expect(
        renderedFontFamily(tester, 'What can we do better?'),
        'NotBundledFont',
      );
    });
  });
}
