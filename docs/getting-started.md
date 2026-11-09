# Getting started

The Flutter SDK runs in iOS, Android, macOS, and web apps.

To send your first event, add `posthog_flutter`, then call `setup` once before `runApp` with your project token and host from your [project settings](https://app.posthog.com/project/settings).

Use `capture` for your own events, and call `flush` and `close` before the app exits.

Install the package:

```bash
flutter pub add posthog_flutter
```

Initialize the SDK once, before `runApp`, with your project token and host:

```dart
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = PostHogConfig('<ph_project_token>');
  config.host = 'https://us.i.posthog.com';
  await Posthog().setup(config);

  runApp(const MyApp());
}
```

Capture an event and identify the user:

```dart
await Posthog().capture(eventName: 'user_signed_up', properties: {'plan': 'free'});
await Posthog().identify(userId: 'user_123', userProperties: {'email': 'a@example.com'});
```

Flush queued events and shut the SDK down before the app exits:

```dart
await Posthog().flush();
await Posthog().close();
```
