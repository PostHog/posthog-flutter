import 'package:flutter/material.dart';
import '../models/posthog_display_survey_text_content_type.dart';
import '../models/survey_appearance.dart';
import 'survey_button.dart';

/// Intro screen shown before the first question — the leading mirror of
/// [ConfirmationMessage]. Advancing records no response and sends no survey
/// event; it is a pure UI transition handled by the bottom sheet.
class IntroMessage extends StatelessWidget {
  const IntroMessage({
    super.key,
    required this.onStart,
    this.appearance = SurveyAppearance.defaultAppearance,
    this.introScreenDescriptionContentType,
  });

  final VoidCallback onStart;
  final SurveyAppearance appearance;
  final PostHogDisplaySurveyTextContentType? introScreenDescriptionContentType;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (appearance.introScreenHeader?.isNotEmpty == true)
          Text(
            appearance.introScreenHeader!,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: appearance.descriptionTextColor,
            ),
            textAlign: TextAlign.center,
          ),
        if (appearance.introScreenDescription?.isNotEmpty == true &&
            introScreenDescriptionContentType ==
                PostHogDisplaySurveyTextContentType.text) ...[
          const SizedBox(height: 16),
          Text(
            appearance.introScreenDescription!,
            style: TextStyle(
              fontSize: 16,
              color: appearance.descriptionTextColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        SurveyButton(
          onPressed: onStart,
          text: appearance.introScreenButtonText,
          appearance: appearance,
        ),
      ],
    );
  }
}
