import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey_appearance.dart';
import 'package:posthog_flutter/src/surveys/models/survey_appearance.dart';

void main() {
  // Builds a SurveyAppearance whose background comes from [background] parsed as
  // a CSS value by fromPostHog.
  SurveyAppearance withBackground(String background) {
    return SurveyAppearance.fromPostHog(
      PostHogDisplaySurveyAppearance(backgroundColor: background),
    );
  }

  group('color parsing', () {
    test('reads a hex value', () {
      expect(
          withBackground('#ff0000').backgroundColor, const Color(0xFFFF0000));
    });

    test('reads a CSS color name', () {
      expect(withBackground('red').backgroundColor, const Color(0xFFFF0000));
    });

    test('reads an rgb() value', () {
      expect(
        withBackground('rgb(255, 0, 0)').backgroundColor,
        const Color(0xFFFF0000),
      );
    });

    test('reads an rgba() value with alpha', () {
      expect(
        withBackground('rgba(255, 0, 0, 0.5)').backgroundColor.toARGB32(),
        0x80FF0000,
      );
    });

    test('reads an hsl() value', () {
      expect(withBackground('hsl(0, 100%, 50%)').backgroundColor,
          const Color(0xFFFF0000));
    });

    test('reads an hsla() value with alpha', () {
      expect(
        withBackground('hsla(0, 100%, 50%, 0.5)').backgroundColor.toARGB32(),
        0x80FF0000,
      );
    });

    test('falls back to the default for a value it cannot read', () {
      // var(...) cannot be resolved on Flutter, so the default white is kept.
      expect(
        withBackground('var(--survey-bg)').backgroundColor,
        Colors.white,
      );
    });
  });

  group('appearance override', () {
    test('override color replaces the derived palette', () {
      final appearance = SurveyAppearance.fromPostHog(
        const PostHogDisplaySurveyAppearance(backgroundColor: '#ffffff'),
        override: const SurveyAppearance(
          backgroundColor: Color(0xFF111111),
          questionTextColor: Colors.white,
        ),
      );

      expect(appearance.backgroundColor, const Color(0xFF111111));
      expect(appearance.questionTextColor, Colors.white);
    });

    test('override keeps server content such as the submit button text', () {
      final appearance = SurveyAppearance.fromPostHog(
        const PostHogDisplaySurveyAppearance(submitButtonText: 'Send'),
        override: const SurveyAppearance(backgroundColor: Color(0xFF111111)),
      );

      expect(appearance.submitButtonText, 'Send');
    });
  });
}
