import 'package:flutter/material.dart';
import '../models/posthog_display_survey_rating_type.dart';
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
    this.scaleLowerBound = 1,
    this.scaleUpperBound = 5,
    this.type = PostHogDisplaySurveyRatingType.number,
    this.lowerBoundLabel,
    this.upperBoundLabel,
    this.appearance = SurveyAppearance.defaultAppearance,
  });

  final String? question;
  final String? description;
  final String? buttonText;
  final bool optional;
  final int scaleLowerBound;
  final int scaleUpperBound;
  final PostHogDisplaySurveyRatingType type;
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
    // Generate a list of integers from scaleLowerBound to scaleUpperBound (inclusive)
    return List<int>.generate(
      widget.scaleUpperBound - widget.scaleLowerBound + 1,
      (i) => widget.scaleLowerBound + i,
    );
  }

  RatingIconType _getRatingIconType(int index) {
    final range = widget.scaleUpperBound - widget.scaleLowerBound + 1;

    if (range == 3) {
      // 3-point scale
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
    } else if (range == 5) {
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

    // Use number display for other scales
    return RatingIconType.neutral;
  }

  Widget _buildRatingButton(int value) {
    final isSelected = _rating == value;

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

    // Show emoji ratings when display == .emoji and scale is 3-point or 5-point
    final range = widget.scaleUpperBound - widget.scaleLowerBound + 1;
    if (widget.type == PostHogDisplaySurveyRatingType.emoji &&
        (range == 3 || range == 5)) {
      final buttonColor =
          isSelected ? Colors.black : Colors.black.withAlpha(128);
      // Convert value to 0-based index.
      // When scaleLowerBound is zero (NPS), the index is the same as the value.
      final index = value - widget.scaleLowerBound;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: RatingIcon(
            type: _getRatingIconType(index),
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
        if (widget.type == PostHogDisplaySurveyRatingType.emoji)
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
              children: _ratingRange
                  .map((value) => _buildRatingButton(value))
                  .toList(),
            ),
          ),
        if (widget.lowerBoundLabel != null || widget.upperBoundLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
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
