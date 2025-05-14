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
  @override
  void initState() {
    super.initState();
    widget.onShown(widget.survey);
  }

  void _handleResponse(int index, String response) {
    widget.onResponse(widget.survey, index, response);
  }

  void _handleClose({bool completed = false}) {
    widget.onClosed(widget.survey, completed);
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
                child: Text(
                  survey.title,
                  style: Theme.of(context).textTheme.titleLarge,
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
          ...survey.questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  question.text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (question.type == 'open') ...[
                  TextField(
                    decoration: InputDecoration(
                      hintText: question.placeholder ?? 'Enter your response',
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (value) => _handleResponse(index, value),
                  ),
                ] else if (question.type == 'multiple_choice') ...[
                  ...question.choices.asMap().entries.map((choice) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton(
                        onPressed: () {
                          _handleResponse(index, choice.value);
                          if (index == survey.questions.length - 1) {
                            _handleClose(completed: true);
                          }
                        },
                        child: Text(choice.value),
                      ),
                    );
                  }).toList(),
                ],
                const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}
