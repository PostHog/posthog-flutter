import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';

class QuestionHeader extends StatelessWidget {
  const QuestionHeader({
    super.key,
    required this.question,
    this.description,
    required this.appearance,
  });

  final String? question;
  final String? description;
  final SurveyAppearance appearance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question != null) ...[
          Text(
            question!,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
        if (description?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: TextStyle(
              fontSize: 16,
              color: appearance.descriptionTextColor ?? Colors.black,
            ),
          ),
        ],
      ],
    );
  }
}
