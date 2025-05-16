import 'package:flutter/foundation.dart';
import 'question_type.dart';

/// Rating type for survey questions
enum PostHogDisplaySurveyRatingType {
  number('number'),
  stars('stars');

  const PostHogDisplaySurveyRatingType(this.value);
  final String value;

  static PostHogDisplaySurveyRatingType fromString(String type) {
    return PostHogDisplaySurveyRatingType.values.firstWhere(
      (e) => e.value == type.toLowerCase(),
      orElse: () => PostHogDisplaySurveyRatingType.number,
    );
  }

  @override
  String toString() => value;
}

/// Base class for all survey questions
@immutable
abstract class PostHogDisplaySurveyQuestion {
  const PostHogDisplaySurveyQuestion({
    required this.type,
    required this.question,
    this.description,
    this.optional = false,
    this.buttonText,
  });

  final PostHogSurveyQuestionType type;
  final String question;
  final String? description;
  final bool optional;
  final String? buttonText;
}

/// Open text question type
@immutable
class PostHogDisplayOpenQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayOpenQuestion({
    required String question,
    String? description,
    bool optional = false,
    String? buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.open,
          question: question,
          description: description,
          optional: optional,
          buttonText: buttonText,
        );
}

/// Link question type
@immutable
class PostHogDisplayLinkQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayLinkQuestion({
    required String question,
    required this.link,
    String? description,
    bool optional = false,
    String? buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.link,
          question: question,
          description: description,
          optional: optional,
          buttonText: buttonText,
        );

  final String link;
}

/// Rating question type
@immutable
class PostHogDisplayRatingQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayRatingQuestion({
    required String question,
    required this.ratingType,
    required this.lowerBound,
    required this.upperBound,
    required this.lowerBoundLabel,
    required this.upperBoundLabel,
    String? description,
    bool optional = false,
    String? buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.rating,
          question: question,
          description: description,
          optional: optional,
          buttonText: buttonText,
        );

  final PostHogDisplaySurveyRatingType ratingType;
  final int lowerBound;
  final int upperBound;
  final String lowerBoundLabel;
  final String upperBoundLabel;
}

/// Multiple choice question type
@immutable
class PostHogDisplayChoiceQuestion extends PostHogDisplaySurveyQuestion {
  const PostHogDisplayChoiceQuestion({
    required String question,
    required this.choices,
    required this.isMultipleChoice,
    this.hasOpenChoice = false,
    this.shuffleOptions = false,
    String? description,
    bool optional = false,
    String? buttonText,
  }) : super(
          type: PostHogSurveyQuestionType.multipleChoice,
          question: question,
          description: description,
          optional: optional,
          buttonText: buttonText,
        );

  final List<String> choices;
  final bool isMultipleChoice;
  final bool hasOpenChoice;
  final bool shuffleOptions;
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
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'rating':
          return PostHogDisplayRatingQuestion(
            question: question,
            ratingType: PostHogDisplaySurveyRatingType.fromString(q['ratingType'] as String),
            lowerBound: q['lowerBound'] as int,
            upperBound: q['upperBound'] as int,
            lowerBoundLabel: q['lowerBoundLabel'] as String,
            upperBoundLabel: q['upperBoundLabel'] as String,
            description: questionDescription,
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
            description: questionDescription,
            optional: optional,
            buttonText: buttonText,
          );
        case 'open':
        default:
          return PostHogDisplayOpenQuestion(
            question: question,
            description: questionDescription,
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
