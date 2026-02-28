import 'package:flutter/material.dart';

import '../models/survey_appearance.dart';
import '../models/posthog_display_survey_text_content_type.dart';
import 'question_header.dart';
import 'survey_button.dart';

/// A widget that displays a link question in a survey.
class LinkQuestion extends StatelessWidget {
  const LinkQuestion({
    super.key,
    required this.question,
    required this.description,
    this.descriptionContentType,
    required this.appearance,
    required this.onPressed,
    this.buttonText,
    this.link,
  });

  final String question;
  final String? description;
  final PostHogDisplaySurveyTextContentType? descriptionContentType;
  final SurveyAppearance appearance;
  final Future<void> Function() onPressed;
  final String? buttonText;
  final String? link;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionHeader(
          question: question,
          description: description,
          descriptionContentType: descriptionContentType,
          appearance: appearance,
        ),
        const SizedBox(height: 16),
        SurveyButton(
          onPressed: onPressed,
          text: buttonText ?? appearance.submitButtonText,
          appearance: appearance,
        ),
      ],
    );
  }
}
