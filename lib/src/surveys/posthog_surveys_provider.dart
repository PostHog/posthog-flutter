import 'package:flutter/material.dart';

import 'models/posthog_display_survey.dart';
import 'models/question_type.dart';
import 'models/survey_appearance.dart';
import 'models/survey_callbacks.dart';

import 'widgets/link_question.dart';
import 'widgets/open_text_question.dart';
import 'widgets/rating_question.dart';
import 'widgets/choice_question.dart';
import 'widgets/unimplemented_question.dart';
import 'widgets/confirmation_message.dart';
import 'models/rating_question.dart';
import '../posthog_flutter_io.dart';
import '../posthog_flutter_platform_interface.dart';

extension PostHogDisplaySurveyExtension on PostHogDisplaySurvey {
  String get title => name;
  String? get description => questions.firstOrNull?.description;
}

class PostHogSurveysProvider extends StatefulWidget {
  final Widget child;
  static final GlobalKey<PostHogSurveysProviderState> globalKey =
      GlobalKey<PostHogSurveysProviderState>();

  PostHogSurveysProvider({Key? key, required this.child})
      : super(key: globalKey);

  @override
  PostHogSurveysProviderState createState() => PostHogSurveysProviderState();
}

class PostHogSurveysProviderState extends State<PostHogSurveysProvider> {
  Future<void> showSurvey(
    PostHogDisplaySurvey survey,
    OnSurveyShown onShown,
    OnSurveyResponse onResponse,
    OnSurveyClosed onClosed,
  ) async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (context) => SurveyBottomSheet(
        survey: survey,
        onShown: onShown,
        onResponse: onResponse,
        onClosed: onClosed,
        appearance: SurveyAppearance.fromPostHog(survey.appearance),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

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
              response ?? '',
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
          onLinkClick: (url) async {
            await (PosthogFlutterPlatformInterface.instance as PosthogFlutterIO)
                .openUrl(url);
          },
          onSubmit: (response) async {
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response ?? '',
            );
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
      case PostHogSurveyQuestionType.rating:
        final ratingQuestion = currentQuestion;
        RatingScale scale;
        RatingDisplay display;

        switch (ratingQuestion.type) {
          case PostHogSurveyQuestionType.rating:
            scale = RatingScale.fivePoint;
            display = RatingDisplay.number;
            break;
          default:
            scale = RatingScale.fivePoint;
            display = RatingDisplay.number;
        }

        return RatingQuestion(
          key: ValueKey('rating_question_$_currentIndex'),
          question: ratingQuestion.question,
          description: ratingQuestion.description,
          appearance: SurveyAppearance.fromPostHog(widget.survey.appearance),
          buttonText: ratingQuestion.buttonText,
          optional: ratingQuestion.optional,
          scale: scale,
          display: display,
          lowerBoundLabel: null,
          upperBoundLabel: null,
          onSubmit: (response) async {
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response.toString(),
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
          isMultipleChoice: currentQuestion.type == PostHogSurveyQuestionType.multipleChoice,
          onSubmit: (response) async {
            final nextQuestion = await widget.onResponse(
              widget.survey,
              _currentIndex,
              response is List ? response.join(',') : (response ?? ''),
            );
            setState(() {
              _currentIndex = nextQuestion.questionIndex;
              _isCompleted = nextQuestion.isSurveyCompleted;
            });
          },
        );
      default:
        return UnimplementedQuestion(
          question: currentQuestion.question,
          description: currentQuestion.description,
          type: currentQuestion.type.toString(),
          appearance: const SurveyAppearance(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
              const SizedBox(height: 8),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
