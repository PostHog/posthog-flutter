import 'package:flutter/foundation.dart';

/// Appearance configuration for surveys
@immutable
class PostHogDisplaySurveyAppearance {
  const PostHogDisplaySurveyAppearance({
    this.fontFamily,
    this.backgroundColor,
    this.borderColor,
    this.submitButtonColor,
    this.submitButtonText,
    this.submitButtonTextColor,
    this.descriptionTextColor,
    this.ratingButtonColor,
    this.ratingButtonActiveColor,
    this.placeholder,
    this.displayThankYouMessage = true,
    this.thankYouMessageHeader,
    this.thankYouMessageDescription,
    this.thankYouMessageCloseButtonText,
  });

  final String? fontFamily;
  final String? backgroundColor;
  final String? borderColor;
  final String? submitButtonColor;
  final String? submitButtonText;
  final String? submitButtonTextColor;
  final String? descriptionTextColor;
  final String? ratingButtonColor;
  final String? ratingButtonActiveColor;
  final String? placeholder;
  final bool displayThankYouMessage;
  final String? thankYouMessageHeader;
  final String? thankYouMessageDescription;
  final String? thankYouMessageCloseButtonText;
}
