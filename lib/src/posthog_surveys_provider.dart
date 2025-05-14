import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

extension PostHogDisplaySurveyExtension on PostHogDisplaySurvey {
  String? get description => null;
  List<PostHogDisplayQuestion> get questions => [];
}

class PostHogDisplayQuestion {
  final String text;
  final String type;
  final String? placeholder;
  final List<String> choices;

  PostHogDisplayQuestion({
    required this.text,
    required this.type,
    this.placeholder,
    this.choices = const [],
  });
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

  const SurveyBottomSheet({
    Key? key,
    required this.survey,
    required this.onShown,
    required this.onResponse,
    required this.onClosed,
  }) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    final survey = widget.survey;
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding =
        mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      survey.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _handleClose(),
              ),
            ],
          ),
          if (survey.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              survey.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Current Index: $_currentIndex',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                if (!_isCompleted) ...[
                  ElevatedButton(
                    onPressed: () async {
                      final nextQuestion = await widget.onResponse(
                          widget.survey,
                          _currentIndex,
                          'Response for $_currentIndex');
                      setState(() {
                        _currentIndex = nextQuestion.questionIndex;
                        _isCompleted = nextQuestion.isSurveyCompleted;
                      });
                    },
                    child: const Text('Next Question'),
                  ),
                ] else ...[
                  const Text(
                    'Thank you for completing the survey!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _handleClose(),
                    child: const Text('Close'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
