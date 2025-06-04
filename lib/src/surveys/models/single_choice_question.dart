

class SingleChoiceQuestion {
  const SingleChoiceQuestion({
    required this.question,
    this.description,
    required this.choices,
    this.buttonText,
    this.optional = false,
    this.hasOpenChoice = false,
  });

  final String question;
  final String? description;
  final List<String> choices;
  final String? buttonText;
  final bool optional;
  final bool hasOpenChoice;

  factory SingleChoiceQuestion.fromJson(Map<String, dynamic> json) {
    return SingleChoiceQuestion(
      question: json['question'] as String,
      description: json['description'] as String?,
      choices: (json['choices'] as List<dynamic>).cast<String>(),
      buttonText: json['buttonText'] as String?,
      optional: json['optional'] as bool? ?? false,
      hasOpenChoice: json['hasOpenChoice'] as bool? ?? false,
    );
  }
}
