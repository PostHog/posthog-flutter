import 'dart:io';

import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() {
  /// Wait until the platform channel is properly initialized so we can call
  /// `setContext` during the app initialization.
  WidgetsFlutterBinding.ensureInitialized();

  /// The `context.device.token` is a special property.
  /// When you define it, setting the context again with no token property (ex: `{}`)
  /// has no effect on cleaning up the device token.
  ///
  /// This is used as an example to allow you to set string-based
  /// device tokens, which is the use case when integrating with
  /// Firebase Cloud Messaging (FCM).
  ///
  /// This plugin currently does not support Apple Push Notification service (APNs)
  /// tokens, which are binary structures.
  ///
  /// Aside from this special use case, any other context property that needs
  /// to be defined (or re-defined) can be done.
  Posthog().setContext({
    'device': {
      'token': 'testing',
    }
  });

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Posthog().screen(
      screenName: 'Example Screen',
    );
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Posthog example app'),
        ),
        body: Column(
          children: <Widget>[
            Spacer(),
            Center(
              child: TextButton(
                child: Text('CAPTURE ACTION WITH POSTHOG'),
                onPressed: () {
                  Posthog().capture(
                    eventName: 'ButtonClicked',
                    properties: {
                      'foo': 'bar',
                      'number': 1337,
                      'clicked': true,
                    },
                  );
                },
              ),
            ),
            Spacer(),
            Center(
              child: TextButton(
                child: Text('Update Context'),
                onPressed: () {
                  Posthog().setContext({'custom': 123});
                },
              ),
            ),
            Spacer(),
            Center(
              child: TextButton(
                child: Text('Clear Context'),
                onPressed: () {
                  Posthog().setContext({});
                },
              ),
            ),
            Spacer(),
            Center(
              child: TextButton(
                child: Text('Disable'),
                onPressed: () async {
                  await Posthog().disable();
                  Posthog().capture(
                      eventName: 'This event will not be logged',
                      properties: {});
                },
              ),
            ),
            Spacer(),
            Center(
              child: TextButton(
                child: Text('Enable'),
                onPressed: () async {
                  await Posthog().enable();
                  Posthog().capture(
                      eventName: 'Enabled capturing events!', properties: {});
                },
              ),
            ),
            Spacer(),
            Platform.isIOS
                ? Center(
                    child: TextButton(
                      child: Text('Debug mode'),
                      onPressed: () {
                        Posthog().debug(true);
                      },
                    ),
                  )
                : Container(),
            Spacer(),
          ],
        ),
      ),
      navigatorObservers: [
        PosthogObserver(),
      ],
    );
  }
}
