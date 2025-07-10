import 'package:flutter/material.dart';

import '../models/survey_appearance.dart';
import 'question_header.dart';
import 'survey_button.dart';
import 'survey_choice_button.dart';

class ChoiceQuestionWidget extends StatefulWidget {
  const ChoiceQuestionWidget({
    super.key,
    required this.question,
    required this.description,
    required this.choices,
    required this.appearance,
    this.buttonText,
    this.optional = false,
    this.hasOpenChoice = false,
    required this.onSubmit,
    this.isMultipleChoice = false,
  });

  final String question;
  final String? description;
  final List<String> choices;
  final SurveyAppearance appearance;
  final String? buttonText;
  final bool optional;
  final bool hasOpenChoice;
  final ValueChanged<dynamic> onSubmit;
  final bool isMultipleChoice;

  @override
  State<ChoiceQuestionWidget> createState() => _ChoiceQuestionWidgetState();
}

class _ChoiceQuestionWidgetState extends State<ChoiceQuestionWidget> {
  Set<String> _selectedChoices = {};
  String _openChoiceInput = '';
  final TextEditingController _openChoiceController = TextEditingController();

  void _handleOpenChoiceInput(String value) {
    setState(() {
      _openChoiceInput = value;
    });
  }

  bool get _canSubmit {
    if (widget.optional) return true;
    if (_selectedChoices.isEmpty) return false;
    if (widget.hasOpenChoice &&
        _selectedChoices.contains(widget.choices.last) &&
        _openChoiceInput.trim().isEmpty) {
      return false;
    }
    return true;
  }

  bool _isOpenChoice(String choice) {
    return widget.hasOpenChoice && choice == widget.choices.last;
  }

  void _onSubmit() {
    if (!_canSubmit) return;

    final List<String> result = [];

    // For both single and multiple choice, create a list of selected choices
    for (final choice in _selectedChoices) {
      if (_isOpenChoice(choice)) {
        result.add(_openChoiceInput.trim());
      } else {
        result.add(choice);
      }
    }

    // Always submit a List<String>, even for single choice (will be a list with one element)
    // This will be handled by native SDK code to send the correct response format upstream
    widget.onSubmit(result);
  }

  @override
  void dispose() {
    _openChoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final headerFooterHeight = 350; //estimated
    final availableHeight =
        screenHeight - headerFooterHeight - keyboardHeight - bottomPadding;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fixed header
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QuestionHeader(
              question: widget.question,
              description: widget.description,
              appearance: widget.appearance,
            ),
            const SizedBox(height: 16),
          ],
        ),
        // Scrollable choices - use full screen height minus insets
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: availableHeight,
            minHeight: 0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...widget.choices.map((choice) {
                  final isSelected = _selectedChoices.contains(choice);
                  final isOpenChoice = _isOpenChoice(choice);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurveyChoiceButton(
                      label: choice,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          if (widget.isMultipleChoice) {
                            if (_selectedChoices.contains(choice)) {
                              _selectedChoices.remove(choice);
                            } else {
                              _selectedChoices.add(choice);
                            }
                          } else {
                            if (_selectedChoices.contains(choice)) {
                              _selectedChoices.clear();
                            } else {
                              _selectedChoices = {choice};
                            }
                          }
                        });
                      },
                      appearance: widget.appearance,
                      isOpenChoice: isOpenChoice,
                      openChoiceInput: _openChoiceInput,
                      onOpenChoiceChanged:
                          isOpenChoice ? _handleOpenChoiceInput : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Fixed submit button
        SurveyButton(
          onPressed: _canSubmit ? _onSubmit : null,
          text: widget.buttonText ?? widget.appearance.submitButtonText,
          appearance: widget.appearance,
        ),
      ],
    );
  }
}
