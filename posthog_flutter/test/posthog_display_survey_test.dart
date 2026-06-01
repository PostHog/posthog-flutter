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

  group('PostHogDisplaySurvey.fromDict link question', () {
    test('parses a real URL unchanged', () {
      final question = firstLinkQuestion(surveyWithLink('https://posthog.com'));
      expect(question.link, 'https://posthog.com');
    });

    test('iOS payload: empty-string link parses to an empty string', () {
      // posthog-ios maps a missing URL to "" (question.link ?? "") before it
      // reaches the Flutter bridge, so the Dart layer receives "".
      final question = firstLinkQuestion(surveyWithLink(''));
      expect(question.link, '');
    });

    test('Android payload: null link does not throw and parses to empty string',
        () {
      // posthog-android has no "" fallback, so the Flutter bridge forwards a
      // raw null. This is issue #407: a non-null cast threw here and silently
      // dropped the whole survey on Android while iOS rendered fine.
      expect(
        () => firstLinkQuestion(surveyWithLink(null)),
        returnsNormally,
      );
      expect(firstLinkQuestion(surveyWithLink(null)).link, '');
    });

    test('absent link key parses to an empty string', () {
      final question = firstLinkQuestion(surveyWithLink(_absent));
      expect(question.link, '');
    });
  });
}

/// Sentinel meaning "omit the `link` key entirely" (distinct from `null`).
const Object _absent = Object();
