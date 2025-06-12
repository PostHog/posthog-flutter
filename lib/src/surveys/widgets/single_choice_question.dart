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

class _SingleChoiceQuestionWidgetState
    extends State<SingleChoiceQuestionWidget> {
  String? _selectedChoice;
  String _openChoiceInput = '';
  final TextEditingController _openChoiceController = TextEditingController();
  double _headerHeight = 0;
  double _contentHeight = 0;
  double _buttonHeight = 0;

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
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fixed header
            LayoutBuilder(
              builder: (context, headerConstraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print("Header height is ${headerConstraints.maxHeight}");
                  if (mounted && _headerHeight != headerConstraints.maxHeight) {
                    setState(() {
                      _headerHeight = headerConstraints.maxHeight;
                    });
                  }
                });

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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print("Content height is ${contentConstraints.maxHeight}");
                  if (mounted &&
                      _contentHeight != contentConstraints.maxHeight) {
                    setState(() {
                      _contentHeight = contentConstraints.maxHeight;
                    });
                  }
                });

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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  print("button height is ${buttonConstraints.maxHeight}");
                  if (mounted && _buttonHeight != buttonConstraints.maxHeight) {
                    setState(() {
                      _buttonHeight = buttonConstraints.maxHeight;
                    });
                  }
                });

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
