import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_observer.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_link_question.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/surveys/widgets/survey_bottom_sheet.dart';

void main() {
  // Builds a minimal survey dict (as forwarded by the native method channel)
  // whose single question is of type `link`. When [includeLink] is false the
  // `link` key is omitted entirely; otherwise it is set to [link], which may be
  // null to mirror the Android bridge.
  Map<String, Object?> surveyWithLinkQuestion({
    Object? link,
    bool includeLink = true,
  }) {
    return {
      'id': 'survey-1',
      'name': 'Test survey',
      'questions': [
        {
          'type': 'link',
          'question': 'Welcome',
          'isOptional': false,
          if (includeLink) 'link': link,
        },
      ],
    };
  }

  PostHogDisplayLinkQuestion firstLinkQuestion(Map<String, Object?> dict) {
    final survey = PostHogDisplaySurvey.fromDict(dict);
    return survey.questions.first as PostHogDisplayLinkQuestion;
  }

  testWidgets('shows and hides surveys using the root navigator', (
    tester,
  ) async {
    addTearDown(() {
      SurveyService().hideSurvey();
      PosthogObserver.clearCurrentContext();
    });

    final rootNavigatorKey = GlobalKey<NavigatorState>();
    final nestedNavigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: Navigator(
          key: nestedNavigatorKey,
          observers: [PosthogObserver()],
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Nested route')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final showSurvey = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict(surveyWithLinkQuestion(link: '')),
      (_) {},
      (_, __, ___) => throw UnimplementedError(),
      (_) {},
    );
    await tester.pumpAndSettle();

    final surveyContext = tester.element(find.byType(SurveyBottomSheet));
    expect(Navigator.of(surveyContext), same(rootNavigatorKey.currentState));

    final pushedRoute = rootNavigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('New root route')),
      ),
    );
    await tester.pumpAndSettle();

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await showSurvey;

    expect(find.text('New root route'), findsOneWidget);
    expect(find.byType(SurveyBottomSheet, skipOffstage: false), findsNothing);

    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await pushedRoute;
    expect(find.text('Nested route'), findsOneWidget);

    final immediatelyHiddenSurvey = SurveyService().showSurvey(
      PostHogDisplaySurvey.fromDict(surveyWithLinkQuestion(link: '')),
      (_) {},
      (_, __, ___) => throw UnimplementedError(),
      (_) {},
    );
    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
    await immediatelyHiddenSurvey;

    expect(find.byType(SurveyBottomSheet), findsNothing);
  });

  group('PostHogDisplaySurvey.fromDict link question', () {
    // (description, native link payload, expected parsed link)
    const cases = <(String, Object?, String)>[
      (
        'parses a real URL unchanged',
        'https://posthog.com',
        'https://posthog.com',
      ),
      // posthog-ios maps a missing URL to "" before the Flutter bridge sees it.
      ('iOS payload: empty-string link parses to an empty string', '', ''),
      // posthog-android forwards a raw null instead (issue #407 crash site).
      ('Android payload: null link parses to empty string', null, ''),
    ];

    for (final (description, link, expected) in cases) {
      test(description, () {
        final question = firstLinkQuestion(surveyWithLinkQuestion(link: link));
        expect(question.link, expected);
      });
    }

    test('absent link key parses to an empty string', () {
      final question = firstLinkQuestion(
        surveyWithLinkQuestion(includeLink: false),
      );
      expect(question.link, '');
    });
  });
}
