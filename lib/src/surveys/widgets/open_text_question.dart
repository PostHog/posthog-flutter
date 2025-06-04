import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';
import 'question_header.dart';
import 'survey_button.dart';

class OpenTextQuestion extends StatefulWidget {
  const OpenTextQuestion({
    super.key,
    required this.question,
    required this.description,
    required this.onSubmit,
    this.buttonText = 'Submit',
    this.optional = false,
    this.appearance = SurveyAppearance.defaultAppearance,
  });

  final String? question;
  final String? description;
  final String buttonText;
  final bool optional;
  final SurveyAppearance appearance;
  final void Function(String) onSubmit;

  @override
  State<OpenTextQuestion> createState() => _OpenTextQuestionState();
}

class _OpenTextQuestionState extends State<OpenTextQuestion> {
  String? _response;

  bool get _canSubmit {
    if (widget.optional) return true;
    return _response?.isNotEmpty == true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final availableHeight = mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            mediaQuery.padding.bottom;

        // Reserve space for header and button (approximate)
        final reservedSpace = 150.0;
        final textFieldMaxHeight = (availableHeight - reservedSpace) * 0.7;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuestionHeader(
              question: widget.question,
              description: widget.description,
              appearance: widget.appearance,
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: textFieldMaxHeight,
                minHeight: 80,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: TextField(
                  maxLines: null,
                  minLines: 2,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Start typing...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    contentPadding: const EdgeInsets.all(12),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _response = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SurveyButton(
              onPressed: () => widget.onSubmit(_response?.trim() ?? ""),
              text: widget.buttonText,
              appearance: widget.appearance,
              enabled: _canSubmit,
            ),
          ],
        );
      },
    );
  }
}
