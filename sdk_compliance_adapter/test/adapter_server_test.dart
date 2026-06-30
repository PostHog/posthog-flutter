import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  test('compliance_adapter_server', () async {
    final adapter = ComplianceAdapter();
    final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
    await adapter.start(port: port);
    addTearDown(adapter.close);

    await Completer<void>().future;
  }, timeout: Timeout.none);
}
