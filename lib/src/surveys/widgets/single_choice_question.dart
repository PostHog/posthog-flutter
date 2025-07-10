import 'dart:math' as math;

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
  State<SingleChoiceQuestionWidget> createState() =>
      _SingleChoiceQuestionWidgetState();
}

class _SingleChoiceQuestionWidgetState
    extends State<SingleChoiceQuestionWidget> {
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

    if (widget.isMultipleChoice) {
      final List<String> result = [];
      for (final choice in _selectedChoices) {
        if (_isOpenChoice(choice)) {
          result.add(_openChoiceInput.trim());
        } else {
          result.add(choice);
        }
      }
      widget.onSubmit(result);
    } else {
      final selectedChoice =
          _selectedChoices.isEmpty ? null : _selectedChoices.first;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fixed header
            LayoutBuilder(
              builder: (context, headerConstraints) {
                return Column(
                  children: [
                    QuestionHeader(
                      question: widget.question,
                      description: widget.description,
                      appearance: widget.appearance,
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            // Scrollable choices
            LayoutBuilder(
              builder: (context, contentConstraints) {
                return Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(0, 400),
                      minHeight: 0,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...widget.choices.map((choice) {
                            final isSelected =
                                _selectedChoices.contains(choice);
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
                                onOpenChoiceChanged: isOpenChoice
                                    ? _handleOpenChoiceInput
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Fixed footer
            LayoutBuilder(
              builder: (context, buttonConstraints) {
                return SurveyButton(
                  onPressed: _canSubmit ? _onSubmit : null,
                  appearance: widget.appearance,
                  text: widget.buttonText ?? 'Submit',
                );
              },
            ),
          ],
        );
      },
    );
  }
}
