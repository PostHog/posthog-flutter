import 'package:flutter/material.dart';

class QuestionHeader extends StatelessWidget {
  const QuestionHeader({
    super.key,
    required this.question,
    this.description,
  });

  final String? question;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question != null) ...[          
          Text(
            question!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
        if (description?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black87,
                ),
          ),
        ],
      ],
    );
  }
}
