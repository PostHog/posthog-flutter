import 'package:flutter/material.dart';

import '../models/survey_appearance.dart';
import 'question_header.dart';

/// A widget that displays a link question in a survey.
class LinkQuestion extends StatelessWidget {
  const LinkQuestion({
    super.key,
    required this.question,
    required this.description,
    required this.appearance,
    required this.onSubmit,
    required this.onLinkClick,
    this.buttonText,
    this.link,
  });

  final String question;
  final String? description;
  final SurveyAppearance appearance;
  final Future<void> Function(String response) onSubmit;
  final void Function(String url) onLinkClick;
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
          appearance: appearance,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () async {
            await onSubmit('link clicked');
            if (link != null) {
              onLinkClick(link!);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: appearance.submitButtonColor,
            foregroundColor: appearance.submitButtonTextColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(buttonText ?? appearance.submitButtonText),
        ),
      ],
    );
  }
}
