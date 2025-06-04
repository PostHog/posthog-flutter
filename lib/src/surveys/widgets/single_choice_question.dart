import 'package:flutter/material.dart';

import '../models/survey_appearance.dart';
import 'question_header.dart';
import 'survey_button.dart';
import 'survey_choice_button.dart';

class SingleChoiceQuestionWidget extends StatefulWidget {
  const SingleChoiceQuestionWidget({
    super.key,
    required this.question,
    required this.description,
    required this.choices,
    required this.appearance,
    this.buttonText,
    this.optional = false,
    this.hasOpenChoice = false,
    required this.onSubmit,
  });

  final String question;
  final String? description;
  final List<String> choices;
  final SurveyAppearance appearance;
  final String? buttonText;
  final bool optional;
  final bool hasOpenChoice;
  final ValueChanged<String?> onSubmit;

  @override
  State<SingleChoiceQuestionWidget> createState() =>
      _SingleChoiceQuestionWidgetState();
}

class _SingleChoiceQuestionWidgetState extends State<SingleChoiceQuestionWidget> {
  String? _selectedChoice;
  String _openChoiceInput = '';
  final TextEditingController _openChoiceController = TextEditingController();

  void _handleOpenChoiceInput(String value) {
    setState(() {
      _openChoiceInput = value;
    });
  }

  bool get _canSubmit {
    if (widget.optional) return true;
    if (_selectedChoice == null) return false;
    if (_isOpenChoice(_selectedChoice!) && _openChoiceInput.trim().isEmpty) {
      return false;
    }
    return true;
  }

  bool _isOpenChoice(String choice) {
    return widget.hasOpenChoice && choice == widget.choices.last;
  }

  void _onSubmit() {
    if (!_canSubmit) return;

    final selectedChoice = _selectedChoice;
    if (selectedChoice == null) {
      widget.onSubmit(null);
      return;
    }

    if (_isOpenChoice(selectedChoice)) {
      widget.onSubmit(_openChoiceInput.trim());
    } else {
      widget.onSubmit(selectedChoice);
    }
  }

  @override
  void initState() {
    super.initState();
    _openChoiceController.addListener(() {
      _openChoiceInput = _openChoiceController.text;
    });
  }

  @override
  void dispose() {
    _openChoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuestionHeader(
            question: widget.question,
            description: widget.description,
            appearance: widget.appearance,
          ),
          const SizedBox(height: 24),
          ...widget.choices.map((choice) {
            final isSelected = _selectedChoice == choice;
            final isOpenChoice = _isOpenChoice(choice);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurveyChoiceButton(
                label: choice,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedChoice = choice;
                  });
                },
                appearance: widget.appearance,
                isOpenChoice: isOpenChoice,
                openChoiceInput: _openChoiceInput,
                onOpenChoiceChanged: isOpenChoice
                    ? _handleOpenChoiceInput
                    : null,
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
          SurveyButton(
            onPressed: _canSubmit ? _onSubmit : null,
            appearance: widget.appearance,
            text: widget.buttonText ?? 'Submit',
          ),
        ],
      ),
    );
  }
}
