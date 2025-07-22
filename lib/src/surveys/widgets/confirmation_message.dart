import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';
import 'survey_button.dart';

class ConfirmationMessage extends StatelessWidget {
  const ConfirmationMessage({
    super.key,
    required this.onClose,
    this.appearance = SurveyAppearance.defaultAppearance,
  });

  final VoidCallback onClose;
  final SurveyAppearance appearance;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          appearance.thankYouMessageHeader,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: appearance.descriptionTextColor,
          ),
          textAlign: TextAlign.center,
        ),
        if (appearance.thankYouMessageDescription?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text(
            appearance.thankYouMessageDescription!,
            style: TextStyle(
              fontSize: 16,
              color: appearance.descriptionTextColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        SurveyButton(
          onPressed: onClose,
          text: appearance.thankYouMessageCloseButtonText,
          appearance: appearance,
        ),
      ],
    );
  }
}
