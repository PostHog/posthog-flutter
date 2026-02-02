import 'package:flutter/material.dart';
import '../models/survey_appearance.dart';

class NumberRatingButton extends StatelessWidget {
  const NumberRatingButton({
    super.key,
    required this.value,
    required this.isSelected,
    required this.onTap,
    required this.appearance,
    required this.isLastItem,
    required this.isFirstItem,
  });

  final int value;
  final bool isSelected;
  final VoidCallback onTap;
  final SurveyAppearance appearance;
  final bool isLastItem;
  final bool isFirstItem;

  @override
  Widget build(BuildContext context) {
    final buttonColor = isSelected
        ? appearance.ratingButtonActiveColor
        : appearance.ratingButtonColor;

    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 45,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.horizontal(
                    left: isFirstItem ? const Radius.circular(6) : Radius.zero,
                    right: isLastItem ? const Radius.circular(6) : Radius.zero,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: buttonColor,
                            borderRadius: BorderRadius.horizontal(
                              left: isFirstItem
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                              right: isLastItem
                                  ? const Radius.circular(4)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          value.toString(),
                          style: TextStyle(
                            color: isSelected
                                ? appearance.ratingButtonSelectedTextColor
                                : appearance.ratingButtonUnselectedTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!isLastItem)
            Container(
              height: 45,
              width: 1,
              color: appearance.borderColor,
            ),
        ],
      ),
    );
  }
}
