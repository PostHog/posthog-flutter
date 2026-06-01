import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_link_question.dart';

void main() {
  // Builds a minimal survey dict (as forwarded by the native method channel)
  // whose single question is of type `link`, overriding only the `link` value.
  Map<String, dynamic> surveyWithLink(Object? link) {
    final question = <String, dynamic>{
      'type': 'link',
      'question': 'Welcome',
      'isOptional': false,
    };
    // Mirror the native bridges: Android forwards a raw value (possibly null),
    // so a missing URL is represented by the key being present with `null`.
    // Passing the sentinel below lets a caller omit the key entirely.
    if (link != _absent) {
      question['link'] = link;
    }

    return <String, dynamic>{
      'id': 'survey-1',
      'name': 'Test survey',
      'questions': <dynamic>[question],
    };
  }

  PostHogDisplayLinkQuestion firstLinkQuestion(Map<String, dynamic> dict) {
    final survey = PostHogDisplaySurvey.fromDict(dict);
    return survey.questions.first as PostHogDisplayLinkQuestion;
  }

  // (description, native link payload, expected parsed link)
  const cases = <(String, Object?, String)>[
    ('parses a real URL unchanged', 'https://posthog.com', 'https://posthog.com'),
    // posthog-ios maps a missing URL to "" before the Flutter bridge sees it.
    ('iOS payload: empty-string link parses to an empty string', '', ''),
    // posthog-android forwards a raw null instead (issue #407 crash site).
    ('Android payload: null link parses to empty string', null, ''),
    ('absent link key parses to an empty string', _absent, ''),
  ];

  group('PostHogDisplaySurvey.fromDict link question', () {
    for (final (description, input, expected) in cases) {
      test(description, () {
        final question = firstLinkQuestion(surveyWithLink(input));
        expect(question.link, expected);
      });
    }
  });
}

/// Sentinel meaning "omit the `link` key entirely" (distinct from `null`).
const Object _absent = Object();
