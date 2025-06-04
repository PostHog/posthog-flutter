import 'package:flutter/material.dart';
import '../models/rating_question.dart';
import '../models/survey_appearance.dart';
import 'question_header.dart';
import 'survey_button.dart';
import 'rating_icons.dart';
import 'number_rating_button.dart';

class RatingQuestion extends StatefulWidget {
  const RatingQuestion({
    super.key,
    required this.question,
    required this.description,
    required this.onSubmit,
    this.buttonText,
    this.optional = false,
    this.scale = RatingScale.fivePoint,
    this.display = RatingDisplay.number,
    this.lowerBoundLabel,
    this.upperBoundLabel,
    this.appearance = SurveyAppearance.defaultAppearance,
  });

  final String? question;
  final String? description;
  final String? buttonText;
  final bool optional;
  final RatingScale scale;
  final RatingDisplay display;
  final String? lowerBoundLabel;
  final String? upperBoundLabel;
  final SurveyAppearance appearance;
  final void Function(int) onSubmit;

  @override
  State<RatingQuestion> createState() => _RatingQuestionState();
}

class _RatingQuestionState extends State<RatingQuestion> {
  int? _rating;

  bool get _canSubmit {
    if (widget.optional) return true;
    return _rating != null;
  }

  List<int> get _ratingRange {
    switch (widget.scale) {
      case RatingScale.threePoint:
        return [1, 2, 3];
      case RatingScale.fivePoint:
        return [1, 2, 3, 4, 5];
      case RatingScale.oneToFive:
        return [1, 2, 3, 4, 5];
      case RatingScale.oneToTen:
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    }
  }

  RatingIconType _getRatingIconType(int index, bool isThreePoint) {
    if (isThreePoint) {
      switch (index) {
        case 0:
          return RatingIconType.dissatisfied;
        case 1:
          return RatingIconType.neutral;
        case 2:
          return RatingIconType.satisfied;
        default:
          return RatingIconType.neutral;
      }
    } else {
      // 5-point scale
      switch (index) {
        case 0:
          return RatingIconType.veryDissatisfied;
        case 1:
          return RatingIconType.dissatisfied;
        case 2:
          return RatingIconType.neutral;
        case 3:
          return RatingIconType.satisfied;
        case 4:
          return RatingIconType.verySatisfied;
        default:
          return RatingIconType.neutral;
      }
    }
  }

  Widget _buildRatingButton(int value) {
    final isSelected = _rating == value;
    final buttonColor = isSelected
        ? widget.appearance.ratingButtonActiveColor ??
            widget.appearance.submitButtonColor
        : widget.appearance.ratingButtonColor ?? Colors.grey.shade200;

    void onTap() {
      setState(() {
        // If clicking the same value, deselect it
        if (_rating == value) {
          _rating = null; // null represents no selection
        } else {
          _rating = value;
        }
      });
    }

    if (widget.display == RatingDisplay.emoji &&
        [RatingScale.threePoint, RatingScale.fivePoint]
            .contains(widget.scale)) {
      // Convert value to 0-based index
      final index = value - 1;
      final isThreePoint = widget.scale == RatingScale.threePoint;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: RatingIcon(
            type: _getRatingIconType(index, isThreePoint),
            selected: isSelected,
            color: buttonColor,
          ),
        ),
      );
    }

    return NumberRatingButton(
      value: value,
      isSelected: isSelected,
      onTap: onTap,
      appearance: widget.appearance,
      isLastItem: value == _ratingRange.last,
      isFirstItem: value == _ratingRange.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionHeader(
          question: widget.question,
          description: widget.description,
          appearance: widget.appearance,
        ),
        const SizedBox(height: 24),
        if (widget.display == RatingDisplay.emoji)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:
                _ratingRange.map((value) => _buildRatingButton(value)).toList(),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.appearance.borderColor ?? Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: Row(
              children:
                  _ratingRange.map((value) => _buildRatingButton(value)).toList(),
            ),
          ),
        if (widget.lowerBoundLabel != null || widget.upperBoundLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.lowerBoundLabel != null)
                  Text(
                    widget.lowerBoundLabel!,
                    style: TextStyle(
                      color: widget.appearance.descriptionTextColor,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.start,
                  ),
                if (widget.upperBoundLabel != null)
                  Text(
                    widget.upperBoundLabel!,
                    style: TextStyle(
                      color: widget.appearance.descriptionTextColor,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        SurveyButton(
          onPressed: _canSubmit ? () => widget.onSubmit(_rating!) : null,
          text: widget.buttonText ?? 'Submit',
          appearance: widget.appearance,
          enabled: _canSubmit,
        ),
      ],
    );
  }
}
