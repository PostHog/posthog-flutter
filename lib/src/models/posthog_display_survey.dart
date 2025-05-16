import 'package:flutter/foundation.dart';

/// Rating type for survey questions
enum PostHogDisplaySurveyRatingType {
  number,
  emoji,
}

/// Base class for all survey questions
@immutable
abstract class PostHogDisplaySurveyQuestion {
  const PostHogDisplaySurveyQuestion({
    required this.question,
    this.questionDescription,
    this.optional = false,
    this.buttonText,
  });

  final String question;
  final String? questionDescription;
  final bool optional;
  final String? buttonText;
}

/// Open text question type
@immutable
class PostHogDisplayOpenQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayOpenQuestion({
    required super.question,
    super.questionDescription,
    super.optional,
    super.buttonText,
  });
}

/// Link question type
@immutable
class PostHogDisplayLinkQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayLinkQuestion({
    required super.question,
    required this.link,
    super.questionDescription,
    super.optional,
    super.buttonText,
  });

  final String link;
}

/// Rating question type
@immutable
class PostHogDisplayRatingQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayRatingQuestion({
    required super.question,
    required this.ratingType,
    required this.ratingScale,
    required this.lowerBoundLabel,
    required this.upperBoundLabel,
    super.questionDescription,
    super.optional,
    super.buttonText,
  });

  final PostHogDisplaySurveyRatingType ratingType;
  final int ratingScale;
  final String lowerBoundLabel;
  final String upperBoundLabel;
}

/// Choice question type (single or multiple choice)
@immutable
class PostHogDisplayChoiceQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayChoiceQuestion({
    required super.question,
    required this.choices,
    required this.isMultipleChoice,
    this.hasOpenChoice = false,
    this.shuffleOptions = false,
    super.questionDescription,
    super.optional,
    super.buttonText,
  });

  final List<String> choices;
  final bool hasOpenChoice;
  final bool shuffleOptions;
  final bool isMultipleChoice;
}

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
    this.ratingButtonHoverColor,
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
  final String? ratingButtonHoverColor;
  final String? placeholder;
  final bool displayThankYouMessage;
  final String? thankYouMessageHeader;
  final String? thankYouMessageDescription;
  final String? thankYouMessageCloseButtonText;
}

/// Main survey model containing metadata and questions
@immutable
class PostHogDisplaySurvey {
  factory PostHogDisplaySurvey.fromDict(Map<String, dynamic> dict) {
    final questions = (dict['questions'] as List).map((q) {
      final type = q['type'] as String;
      final question = q['question'] as String;
      final optional = q['optional'] as bool;
      final questionDescription = q['questionDescription'] as String?;
      final buttonText = q['buttonText'] as String?;

      switch (type) {
        case 'link':
          return PostHogDisplayLinkQuestion(
            question: question,
            link: q['link'] as String,
            questionDescription: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'rating':
          return PostHogDisplayRatingQuestion(
            question: question,
            ratingType:
                PostHogDisplaySurveyRatingType.values[q['ratingType'] as int],
            ratingScale: q['ratingScale'] as int,
            lowerBoundLabel: q['lowerBoundLabel'] as String,
            upperBoundLabel: q['upperBoundLabel'] as String,
            questionDescription: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'multiple_choice':
        case 'single_choice':
          return PostHogDisplayChoiceQuestion(
            question: question,
            choices: (q['choices'] as List).cast<String>(),
            isMultipleChoice: type == 'multiple_choice',
            hasOpenChoice: q['hasOpenChoice'] as bool,
            shuffleOptions: q['shuffleOptions'] as bool,
            questionDescription: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'open':
        default:
          return PostHogDisplayOpenQuestion(
            question: question,
            questionDescription: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
      }
    }).toList();

    PostHogDisplaySurveyAppearance? appearance;
    if (dict['appearance'] != null) {
      final a = Map<String, dynamic>.from(dict['appearance'] as Map);
      appearance = PostHogDisplaySurveyAppearance(
        fontFamily: a['fontFamily'] as String?,
        backgroundColor: a['backgroundColor'] as String?,
        borderColor: a['borderColor'] as String?,
        submitButtonColor: a['submitButtonColor'] as String?,
        submitButtonText: a['submitButtonText'] as String?,
        submitButtonTextColor: a['submitButtonTextColor'] as String?,
        descriptionTextColor: a['descriptionTextColor'] as String?,
        ratingButtonColor: a['ratingButtonColor'] as String?,
        ratingButtonActiveColor: a['ratingButtonActiveColor'] as String?,
        ratingButtonHoverColor: a['ratingButtonHoverColor'] as String?,
        placeholder: a['placeholder'] as String?,
        displayThankYouMessage: a['displayThankYouMessage'] as bool? ?? true,
        thankYouMessageHeader: a['thankYouMessageHeader'] as String?,
        thankYouMessageDescription: a['thankYouMessageDescription'] as String?,
        thankYouMessageCloseButtonText:
            a['thankYouMessageCloseButtonText'] as String?,
      );
    }

    DateTime? startDate;
    if (dict['startDate'] != null) {
      startDate = DateTime.fromMillisecondsSinceEpoch(dict['startDate'] as int);
    }

    DateTime? endDate;
    if (dict['endDate'] != null) {
      endDate = DateTime.fromMillisecondsSinceEpoch(dict['endDate'] as int);
    }

    return PostHogDisplaySurvey(
      id: dict['id'] as String,
      name: dict['name'] as String,
      questions: questions,
      appearance: appearance,
      startDate: startDate,
      endDate: endDate,
    );
  }

  const PostHogDisplaySurvey({
    required this.id,
    required this.name,
    required this.questions,
    this.appearance,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String name;
  final List<PostHogDisplaySurveyQuestion> questions;
  final PostHogDisplaySurveyAppearance? appearance;
  final DateTime? startDate;
  final DateTime? endDate;
}

/// Response model for next question in survey
@immutable
class PostHogNextSurveyQuestion {
  const PostHogNextSurveyQuestion({
    required this.questionIndex,
    required this.isSurveyCompleted,
  });

  final int questionIndex;
  final bool isSurveyCompleted;
}
