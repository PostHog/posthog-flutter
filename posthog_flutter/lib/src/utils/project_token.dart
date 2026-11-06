import 'package:flutter/foundation.dart';

/// Whether `Posthog.setup` can use [projectToken]. When it can't, logs why
/// and returns false, and setup is skipped.
bool isUsableProjectToken(String projectToken) {
  if (projectToken.isEmpty) {
    debugPrint('[PostHog] projectToken must not be blank. Setup skipped.');
    return false;
  }
  // Capture rejects a personal API key, so it is never sent.
  if (projectToken.startsWith('phx_')) {
    debugPrint(
      '[PostHog] projectToken is a personal API key (phx_), not a project '
      'token. Setup skipped.',
    );
    return false;
  }
  return true;
}
