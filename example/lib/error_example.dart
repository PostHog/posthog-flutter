import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter_example/main.dart';

class ErrorExample {
  void causeUnhandledDivisionError() {
    // This will cause a division by zero error
    10 ~/ 0;
  }

  Future<void> causeHandledDivisionError() async {
    try {
      // This will cause a division by zero error
      10 ~/ 0;
    } catch (e, stackTrace) {
      await Posthog().captureException(
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> throwWithinDelayed() async {
    Future.delayed(Duration.zero, () {
      // does not throw on web here, just with runZonedGuarded handler
      throw const CustomException('Test throwWithinDelayed',
          code: 'PlatformDispatcherTest',
          additionalData: {'test_type': 'platform_dispatcher_error'});
    });
  }

  Future<void> throwWithinTimer() async {
    Future.delayed(Duration.zero, () {
      // does not throw on web here, just with runZonedGuarded handler
      throw const CustomException('Test throwWithinTimer',
          code: 'PlatformDispatcherTest',
          additionalData: {'test_type': 'platform_dispatcher_error'});
    });
  }
}
