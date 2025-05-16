import 'package:flutter/material.dart';
import 'question_header.dart';

class UnimplementedQuestion extends StatelessWidget {
  const UnimplementedQuestion({
    super.key,
    required this.question,
    this.description,
    required this.type,
  });

  final String? question;
  final String? description;
  final String type;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionHeader(
          question: question,
          description: description,
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
