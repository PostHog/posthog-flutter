import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Repro cases for the platform-view mask/reveal spill.
///
/// Two families of case, checked differently in a replay recording:
///
/// * **Spill** — a sentinel banner sits directly below a clipped platform view.
///   The banner is plain Flutter, so replay must always show it. A missing
///   banner means the view's rect overran its visible region and painted over
///   it.
/// * **Orientation** — a revealed platform view shows four coloured quadrants.
///   The native side crops an axis-aligned region of the *screen*, so replay
///   must show the same quadrant in the same corner. A swapped corner means the
///   crop was composited in the view's own space and the view's rotation or
///   flip was applied a second time.
const spillSentinels = <String, String>{
  'clipped_masked': 'SPILLONE',
  'scrolled_masked': 'SPILLTWO',
  'nested_clip_masked': 'SPILLTHREE',
  'clipped_revealed': 'SPILLFOUR',
  'scrolled_revealed': 'SPILLFIVE',
  'masked_over_revealed': 'SPILLSIX',
  'unclipped_masked_control': 'SPILLSEVEN',
};

WebViewController _wv() =>
    WebViewController()..loadRequest(Uri.parse('https://www.wikipedia.org'));

/// Red top-left, blue top-right, yellow bottom-left, magenta bottom-right.
const _quadrantPage = '''
<html><body style="margin:0;display:grid;
grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;height:100vh">
<div style="background:#ff0000"></div><div style="background:#0000ff"></div>
<div style="background:#ffff00"></div><div style="background:#ff00ff"></div>
</body></html>''';

WebViewController _quadrantWv() => WebViewController()
  ..loadRequest(Uri.dataFromString(_quadrantPage, mimeType: 'text/html'));

class _Sentinel extends StatelessWidget {
  final String token;
  const _Sentinel(this.token);

  @override
  Widget build(BuildContext context) => Container(
        height: 90,
        width: double.infinity,
        color: const Color(0xFFFFE24A),
        alignment: Alignment.center,
        child: Text(
          token,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

/// A tall platform view trimmed by a `ClipRect`, sentinel directly below.
class ClippedMasked extends StatefulWidget {
  final PostHogPlatformViewPrivacy privacy;
  final String token;
  const ClippedMasked({super.key, required this.privacy, required this.token});
  @override
  State<ClippedMasked> createState() => _ClippedMaskedState();
}

class _ClippedMaskedState extends State<ClippedMasked> {
  late final WebViewController _c = _wv();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('spill repro')),
        body: Column(
          children: [
            ClipRect(
              child: SizedBox(
                height: 160,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: 520,
                  child: SizedBox(
                    height: 520,
                    child: PostHogPlatformView(
                      privacy: widget.privacy,
                      child: WebViewWidget(controller: _c),
                    ),
                  ),
                ),
              ),
            ),
            _Sentinel(widget.token),
          ],
        ),
      );
}

/// Nested clips: the innermost one wins and the mask must respect it.
class NestedClipMasked extends StatefulWidget {
  final String token;
  const NestedClipMasked({super.key, required this.token});
  @override
  State<NestedClipMasked> createState() => _NestedClipMaskedState();
}

class _NestedClipMaskedState extends State<NestedClipMasked> {
  late final WebViewController _c = _wv();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('spill repro')),
        body: Column(
          children: [
            ClipRect(
              child: SizedBox(
                height: 300,
                child: ClipRect(
                  child: SizedBox(
                    height: 140,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: 520,
                      child: SizedBox(
                        height: 520,
                        child: PostHogPlatformView(
                          privacy: PostHogPlatformViewPrivacy.mask,
                          child: WebViewWidget(controller: _c),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Sentinel(widget.token),
          ],
        ),
      );
}

/// A platform view scrolled half out of a viewport, sentinel pinned below it.
class ScrolledPartlyOut extends StatefulWidget {
  final PostHogPlatformViewPrivacy privacy;
  final String token;
  const ScrolledPartlyOut({
    super.key,
    required this.privacy,
    required this.token,
  });
  @override
  State<ScrolledPartlyOut> createState() => _ScrolledPartlyOutState();
}

class _ScrolledPartlyOutState extends State<ScrolledPartlyOut> {
  late final WebViewController _c = _wv();
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) _controller.jumpTo(260);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('spill repro')),
        body: ListView(
          controller: _controller,
          children: [
            const SizedBox(height: 40),
            SizedBox(
              height: 460,
              child: PostHogPlatformView(
                privacy: widget.privacy,
                child: WebViewWidget(controller: _c),
              ),
            ),
            _Sentinel(widget.token),
            const SizedBox(height: 700),
          ],
        ),
      );
}

/// A masked view directly above a revealed one: the mask must not overrun and
/// black out the view the developer asked to reveal.
class MaskedOverRevealed extends StatefulWidget {
  final String token;
  const MaskedOverRevealed({super.key, required this.token});
  @override
  State<MaskedOverRevealed> createState() => _MaskedOverRevealedState();
}

class _MaskedOverRevealedState extends State<MaskedOverRevealed> {
  late final WebViewController _top = _wv();
  late final WebViewController _bottom = _wv();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('spill repro')),
        body: Column(
          children: [
            ClipRect(
              child: SizedBox(
                height: 150,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: 520,
                  child: SizedBox(
                    height: 520,
                    child: PostHogPlatformView(
                      privacy: PostHogPlatformViewPrivacy.mask,
                      child: WebViewWidget(controller: _top),
                    ),
                  ),
                ),
              ),
            ),
            _Sentinel(widget.token),
            Expanded(
              child: PostHogPlatformView(
                privacy: PostHogPlatformViewPrivacy.capture,
                child: WebViewWidget(controller: _bottom),
              ),
            ),
          ],
        ),
      );
}

/// Control: no clip anywhere. The mask must be unchanged by the fix.
class UnclippedMaskedControl extends StatefulWidget {
  final String token;
  const UnclippedMaskedControl({super.key, required this.token});
  @override
  State<UnclippedMaskedControl> createState() => _UnclippedMaskedControlState();
}

class _UnclippedMaskedControlState extends State<UnclippedMaskedControl> {
  late final WebViewController _c = _wv();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('spill repro')),
        body: Column(
          children: [
            SizedBox(
              height: 200,
              child: PostHogPlatformView(
                privacy: PostHogPlatformViewPrivacy.mask,
                child: WebViewWidget(controller: _c),
              ),
            ),
            _Sentinel(widget.token),
          ],
        ),
      );
}

/// A revealed platform view under a transform, showing four coloured
/// quadrants. Replay must reproduce the quadrants in the same corners as the
/// screen; a swapped corner means the crop was turned or mirrored twice.
class TransformedRevealed extends StatefulWidget {
  /// Null for the control case, which applies no transform.
  final Matrix4? transform;

  /// Trims the view so the clip and the destination are exercised together.
  final bool clipped;

  const TransformedRevealed({
    super.key,
    required this.transform,
    this.clipped = false,
  });

  @override
  State<TransformedRevealed> createState() => _TransformedRevealedState();
}

class _TransformedRevealedState extends State<TransformedRevealed> {
  late final WebViewController _c = _quadrantWv();

  @override
  Widget build(BuildContext context) {
    Widget view = SizedBox(
      width: 300,
      height: 300,
      child: PostHogPlatformView(
        privacy: PostHogPlatformViewPrivacy.capture,
        child: WebViewWidget(controller: _c),
      ),
    );
    if (widget.clipped) {
      view = ClipRect(
        child: SizedBox(
          width: 300,
          height: 150,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: 0,
            maxHeight: 300,
            child: view,
          ),
        ),
      );
    }
    final transform = widget.transform;
    if (transform != null) {
      view = Transform(
        alignment: Alignment.center,
        transform: transform,
        child: view,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('spill repro')),
      body: Center(child: view),
    );
  }
}

/// Every repro case, in the order the device matrix runs them.
List<(String, Widget)> spillCases() => [
      (
        '1_clipped_masked',
        const ClippedMasked(
            privacy: PostHogPlatformViewPrivacy.mask, token: 'SPILLONE')
      ),
      (
        '2_scrolled_masked',
        const ScrolledPartlyOut(
            privacy: PostHogPlatformViewPrivacy.mask, token: 'SPILLTWO')
      ),
      ('3_nested_clip_masked', const NestedClipMasked(token: 'SPILLTHREE')),
      (
        '4_clipped_revealed',
        const ClippedMasked(
            privacy: PostHogPlatformViewPrivacy.capture, token: 'SPILLFOUR')
      ),
      (
        '5_scrolled_revealed',
        const ScrolledPartlyOut(
            privacy: PostHogPlatformViewPrivacy.capture, token: 'SPILLFIVE')
      ),
      ('6_masked_over_revealed', const MaskedOverRevealed(token: 'SPILLSIX')),
      (
        '7_unclipped_control',
        const UnclippedMaskedControl(token: 'SPILLSEVEN')
      ),
      ('8_revealed_untransformed', const TransformedRevealed(transform: null)),
      (
        '9_revealed_quarter_turn',
        TransformedRevealed(transform: Matrix4.rotationZ(1.5707963267948966))
      ),
      (
        '10_revealed_mirrored',
        TransformedRevealed(transform: Matrix4.diagonal3Values(-1, 1, 1))
      ),
      (
        '11_revealed_quarter_turn_clipped',
        TransformedRevealed(
            transform: Matrix4.rotationZ(1.5707963267948966), clipped: true)
      ),
    ];

/// Menu listing every case, so the repros are reachable from the example app.
class PlatformViewSpillScreen extends StatelessWidget {
  const PlatformViewSpillScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cases = spillCases();
    return Scaffold(
      appBar: AppBar(title: const Text('Platform View Spill — Replay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cases 1-7: the yellow sentinel banner must be visible in replay. '
            'Cases 8-11: the four quadrants must appear in replay in the same '
            'corners as on screen.',
          ),
          const SizedBox(height: 16),
          for (final (name, screen) in cases)
            ListTile(
              title: Text(name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => screen,
                  settings: RouteSettings(name: 'spill_$name'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
