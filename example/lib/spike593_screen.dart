import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// SPIKE (#593): cycles native (non-WebView) platform-view cases, 8s each, so
// each one lands in replay. Run with --dart-define=SPIKE593=true.

Widget _native(String kind) => UiKitView(
  viewType: 'spike593/native_view',
  creationParams: {'kind': kind},
  creationParamsCodec: const StandardMessageCodec(),
);

Widget _captured(String kind) => PostHogPlatformView(
  privacy: PostHogPlatformViewPrivacy.capture,
  child: _native(kind),
);

final _cases = <(String, Widget)>[
  ('1 UIKIT CAPTURED', _captured('uikit')),
  ('2 MAPKIT CAPTURED', _captured('mapkit')),
  ('3 METAL FBONLY CAPTURED', _captured('metal')),
  ('4 METAL NOFBO CAPTURED', _captured('metal_fbo_false')),
  (
    '5 MASKED NATIVE OVER CAPTURED',
    Stack(
      children: [
        Positioned.fill(child: _captured('metal')),
        Positioned(
          left: 60,
          top: 60,
          width: 220,
          height: 160,
          child: PostHogPlatformView(
            privacy: PostHogPlatformViewPrivacy.mask,
            child: _native('secret'),
          ),
        ),
      ],
    ),
  ),
  (
    '6 DART MASK OVER CAPTURED',
    Stack(
      children: [
        Positioned.fill(child: _captured('uikit')),
        Positioned(
          left: 60,
          top: 60,
          width: 220,
          height: 120,
          child: PostHogMaskWidget(
            child: Container(
              color: Colors.green,
              alignment: Alignment.center,
              child: const Text(
                'DARTSECRET',
                style: TextStyle(fontSize: 28, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
  (
    '7 MASKED NATIVE UNDER CAPTURED',
    Stack(
      children: [
        Positioned(
          left: 60,
          top: 60,
          width: 220,
          height: 160,
          child: PostHogPlatformView(
            privacy: PostHogPlatformViewPrivacy.mask,
            child: _native('secret'),
          ),
        ),
        Positioned.fill(child: _captured('metal')),
      ],
    ),
  ),
];

class Spike593Screen extends StatefulWidget {
  const Spike593Screen({super.key});

  @override
  State<Spike593Screen> createState() => _Spike593ScreenState();
}

class _Spike593ScreenState extends State<Spike593Screen> {
  var _index = const int.fromEnvironment('SPIKE593_START');
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_index < _cases.length - 1) {
        setState(() => _index++);
        debugPrint('[spike593] case ${_cases[_index].$1}');
      } else {
        _timer?.cancel();
        debugPrint('[spike593] done');
      }
    });
    debugPrint('[spike593] case ${_cases[_index].$1}');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (name, body) = _cases[_index];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: KeyedSubtree(key: ValueKey(_index), child: body),
    );
  }
}
