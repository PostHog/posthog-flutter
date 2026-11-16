import 'package:flutter/foundation.dart';
import 'posthog_display_survey_text_content_type.dart';

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
    this.textColor,
    this.descriptionTextColor,
    this.ratingButtonColor,
    this.ratingButtonActiveColor,
    this.inputBackground,
    this.inputTextColor,
    this.placeholder,
    this.surveyPopupDelaySeconds,
    this.displayThankYouMessage = true,
    this.thankYouMessageHeader,
    this.thankYouMessageDescription,
    this.thankYouMessageDescriptionContentType,
    this.thankYouMessageCloseButtonText,
    this.displayIntroScreen = false,
    this.introScreenHeader,
    this.introScreenDescription,
    this.introScreenDescriptionContentType,
    this.introScreenButtonText,
  });

  final String? fontFamily;
  final String? backgroundColor;
  final String? borderColor;
  final String? submitButtonColor;
  final String? submitButtonText;
  final String? submitButtonTextColor;
  final String? textColor;
  final String? descriptionTextColor;
  final String? ratingButtonColor;
  final String? ratingButtonActiveColor;
  final String? inputBackground;
  final String? inputTextColor;
  final String? placeholder;

  /// Seconds to wait after the survey is triggered before it is shown.
  ///
  /// Null or a non-positive value shows the survey immediately.
  final double? surveyPopupDelaySeconds;
  final bool displayThankYouMessage;
  final String? thankYouMessageHeader;
  final String? thankYouMessageDescription;
  final PostHogDisplaySurveyTextContentType?
      thankYouMessageDescriptionContentType;
  final String? thankYouMessageCloseButtonText;
  final bool displayIntroScreen;
  final String? introScreenHeader;
  final String? introScreenDescription;
  final PostHogDisplaySurveyTextContentType? introScreenDescriptionContentType;
  final String? introScreenButtonText;
}
