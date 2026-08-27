import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Repro cases for the platform-view mask/reveal spill.
///
/// Every case puts a sentinel banner directly below a clipped platform view.
/// The banner is plain Flutter, so replay must always show it — if a case's
/// banner is missing from a replay frame, the platform view's rect overran its
/// visible region and painted over it.
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
    appBar: AppBar(title: const Text("spill repro")),
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
    appBar: AppBar(title: const Text("spill repro")),
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
    appBar: AppBar(title: const Text("spill repro")),
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
    appBar: AppBar(title: const Text("spill repro")),
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
    appBar: AppBar(title: const Text("spill repro")),
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
