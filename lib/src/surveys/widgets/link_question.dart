import 'package:flutter/material.dart';

import '../models/survey_appearance.dart';
import 'question_header.dart';
import 'survey_button.dart';

/// A widget that displays a link question in a survey.
class LinkQuestion extends StatelessWidget {
  const LinkQuestion({
    super.key,
    required this.question,
    required this.description,
    required this.appearance,
    required this.onPressed,
    this.buttonText,
    this.link,
  });

  final String question;
  final String? description;
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
