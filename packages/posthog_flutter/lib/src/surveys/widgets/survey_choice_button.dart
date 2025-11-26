import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';

class SurveyChoiceButton extends StatelessWidget {
  const SurveyChoiceButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.appearance,
    this.isOpenChoice = false,
    this.openChoiceInput = '',
    this.onOpenChoiceChanged,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final SurveyAppearance appearance;
  final bool isOpenChoice;
  final String openChoiceInput;
  final ValueChanged<String>? onOpenChoiceChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? Colors.black
                  : Colors.black.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: isOpenChoice
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label:',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.black.withAlpha(128),
                              fontWeight: isSelected ? FontWeight.bold : null,
                            ),
                          ),
                          TextFormField(
                            key: ValueKey('text_field_${isSelected}_$label'),
                            enabled: isSelected,
                            autofocus: isSelected,
                            onChanged: onOpenChoiceChanged,
                            initialValue: openChoiceInput,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.black.withAlpha(128),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.black
                              : Colors.black.withAlpha(128),
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
                      ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check,
                  size: 16,
                  color: Colors.black,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
