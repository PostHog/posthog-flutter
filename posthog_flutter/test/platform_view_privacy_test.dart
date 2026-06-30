import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_platform_view.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

void main() {
  group('resolvePrivacyPolicyForElement — privacy inheritance', () {
    testWidgets('unwrapped widget inherits the default mask policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(key: Key('leaf')),
        ),
      );
      final element = tester.element(find.byKey(const Key('leaf')));
      final policy = resolvePrivacyPolicyForElement(
          element, PostHogPlatformViewPrivacy.mask);
      expect(policy, PostHogPlatformViewPrivacy.mask);
    });

    testWidgets('capture wrapper overrides an inherited mask policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PostHogPlatformView(
            key: Key('wrapper'),
            privacy: PostHogPlatformViewPrivacy.capture,
            child: SizedBox(),
          ),
        ),
      );
      final element = tester.element(find.byKey(const Key('wrapper')));
      final policy = resolvePrivacyPolicyForElement(
          element, PostHogPlatformViewPrivacy.mask);
      expect(policy, PostHogPlatformViewPrivacy.capture);
    });

    testWidgets('mask wrapper overrides an inherited capture policy',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PostHogPlatformView(
            key: Key('wrapper'),
            privacy: PostHogPlatformViewPrivacy.mask,
            child: SizedBox(),
          ),
        ),
      );
      final element = tester.element(find.byKey(const Key('wrapper')));
      final policy = resolvePrivacyPolicyForElement(
          element, PostHogPlatformViewPrivacy.capture);
      expect(policy, PostHogPlatformViewPrivacy.mask);
    });

    testWidgets('innermost nested wrapper wins over outer wrapper',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PostHogPlatformView(
            key: Key('outer'),
            privacy: PostHogPlatformViewPrivacy.mask,
            child: PostHogPlatformView(
              key: Key('inner'),
              privacy: PostHogPlatformViewPrivacy.capture,
              child: SizedBox(key: Key('leaf')),
            ),
          ),
        ),
      );

      final outerElement = tester.element(find.byKey(const Key('outer')));
      final outerPolicy = resolvePrivacyPolicyForElement(
          outerElement, PostHogPlatformViewPrivacy.capture);
      expect(outerPolicy, PostHogPlatformViewPrivacy.mask);

      final innerElement = tester.element(find.byKey(const Key('inner')));
      final innerPolicy =
          resolvePrivacyPolicyForElement(innerElement, outerPolicy);
      expect(innerPolicy, PostHogPlatformViewPrivacy.capture);

      final leafElement = tester.element(find.byKey(const Key('leaf')));
      final leafPolicy =
          resolvePrivacyPolicyForElement(leafElement, innerPolicy);
      expect(leafPolicy, PostHogPlatformViewPrivacy.capture);
    });
  });
}
