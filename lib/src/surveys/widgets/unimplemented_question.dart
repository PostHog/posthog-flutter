import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';
import 'question_header.dart';

class UnimplementedQuestion extends StatelessWidget {
  const UnimplementedQuestion({
    super.key,
    required this.question,
    this.description,
    required this.type,
    required this.appearance,
  });

  final String? question;
  final String? description;
  final String type;
  final SurveyAppearance appearance;

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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Question type "$type" not yet implemented',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ),
      ],
    );
  }
}
