import 'package:flutter/material.dart';

import '../models/posthog_display_survey.dart';
import '../models/posthog_survey_question_type.dart';
import '../models/survey_appearance.dart';
import '../models/survey_callbacks.dart';
import '../models/posthog_display_link_question.dart';
import '../models/posthog_display_rating_question.dart';
import '../models/posthog_display_choice_question.dart';
import '../../posthog_flutter_platform_interface.dart';

import 'link_question.dart';
import 'open_text_question.dart';
import 'rating_question.dart';
import 'choice_question.dart';
import 'confirmation_message.dart';

/// A bottom sheet that displays a survey to the user.
class SurveyBottomSheet extends StatefulWidget {
  final PostHogDisplaySurvey survey;
  final OnSurveyShown onShown;
  final OnSurveyResponse onResponse;
  final OnSurveyClosed onClosed;
  final SurveyAppearance appearance;

  const SurveyBottomSheet({
    super.key,
    required this.survey,
    required this.onShown,
    required this.onResponse,
    required this.onClosed,
    required this.appearance,
  });

  @override
  State<SurveyBottomSheet> createState() => _SurveyBottomSheetState();
}

class _SurveyBottomSheetState extends State<SurveyBottomSheet> {
  int _currentIndex = 0;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    widget.onShown(widget.survey);
  }

  void _handleClose() {
    widget.onClosed(widget.survey);
    Navigator.of(context).pop();
  }

  Widget _buildQuestion(BuildContext context) {
    final survey = widget.survey;
    final currentQuestion = survey.questions[_currentIndex];

    switch (currentQuestion.type) {
      case PostHogSurveyQuestionType.openText:
        return OpenTextQuestion(
          key: ValueKey('open_text_question_$_currentIndex'),
          question: currentQuestion.question,
          description: currentQuestion.description,
          appearance: SurveyAppearance.fromPostHog(widget.survey.appearance),
          onSubmit: (response) async {
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response,
            );
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
      case PostHogSurveyQuestionType.link:
        final linkQuestion = currentQuestion as PostHogDisplayLinkQuestion;
        return LinkQuestion(
          key: ValueKey('link_question_$_currentIndex'),
          question: linkQuestion.question,
          description: linkQuestion.description,
          appearance: SurveyAppearance.fromPostHog(widget.survey.appearance),
          buttonText: linkQuestion.buttonText,
          link: linkQuestion.link,
          onPressed: () async {
            // Send survey response (true for link questions)
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              true, // Boolean response for link questions
            );

            // Open the URL if provided
            final link = linkQuestion.link;
            if (link.isNotEmpty) {
              await PosthogFlutterPlatformInterface.instance.openUrl(link);
            }

            // Update state
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
      case PostHogSurveyQuestionType.rating:
        final ratingQuestion = currentQuestion as PostHogDisplayRatingQuestion;

        return RatingQuestion(
          key: ValueKey('rating_question_$_currentIndex'),
          question: ratingQuestion.question,
          description: ratingQuestion.description,
          appearance: SurveyAppearance.fromPostHog(widget.survey.appearance),
          buttonText: ratingQuestion.buttonText,
          optional: ratingQuestion.optional,
          scaleLowerBound: ratingQuestion.scaleLowerBound,
          scaleUpperBound: ratingQuestion.scaleUpperBound,
          type: ratingQuestion.ratingType,
          lowerBoundLabel: ratingQuestion.lowerBoundLabel,
          upperBoundLabel: ratingQuestion.upperBoundLabel,
          onSubmit: (response) async {
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response, // Pass integer directly
            );
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
      case PostHogSurveyQuestionType.singleChoice:
      case PostHogSurveyQuestionType.multipleChoice:
        final choiceQuestion = currentQuestion as PostHogDisplayChoiceQuestion;
        return ChoiceQuestionWidget(
          key: ValueKey('choice_question_$_currentIndex'),
          question: choiceQuestion.question,
          description: choiceQuestion.description,
          choices: choiceQuestion.choices,
          appearance: SurveyAppearance.fromPostHog(widget.survey.appearance),
          buttonText: choiceQuestion.buttonText,
          optional: choiceQuestion.optional,
          hasOpenChoice: choiceQuestion.hasOpenChoice,
          isMultipleChoice:
              currentQuestion.type == PostHogSurveyQuestionType.multipleChoice,
          onSubmit: (response) async {
            // Both single and multiple choice questions return List<String>
            // Single choice will be a list with one element
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response,
            );
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: widget.appearance.backgroundColor ?? Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: mediaQuery.viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _handleClose(),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_isCompleted)
                          _buildQuestion(context)
                        else
                          ConfirmationMessage(
                            onClose: _handleClose,
                            appearance: widget.appearance,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
