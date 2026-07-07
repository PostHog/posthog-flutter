import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'main.dart' show exampleReplayConfig, kMaskAllPlatformViews;

const _exampleChannel = MethodChannel('posthog_flutter_example');

void _presentNativeScreen({required bool capture, bool ownWindow = false}) {
  exampleReplayConfig?.captureNativeScreens = capture;
  _exampleChannel.invokeMethod(
    ownWindow ? 'presentNativeScreenOwnWindow' : 'presentNativeScreen',
  );
}

/// Demonstrates session replay with platform views.
///
/// Shows two scenarios:
///  1. Mixed screen — a native WebView embedded in a Flutter Scaffold with
///     app bar, search bar overlay, and bottom navigation. This is the most
///     common real-world case (e.g. a map in a Scaffold).
///  2. Full-screen native view — the WebView fills the entire screen with no
///     surrounding Flutter UI. Represents paywalls, full-screen maps, etc.
class PlatformViewsScreen extends StatelessWidget {
  const PlatformViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform Views — Session Replay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Masked vs captured matrix',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Masked = covered with a black box in replay (default). '
            'Captured = revealed in replay via PostHogPlatformView(privacy: .capture).',
          ),
          const SizedBox(height: 24),
          _CaseCard(
            title: 'Mixed screen — masked',
            subtitle:
                'WebView in a Scaffold (app bar, search, bottom nav). '
                'WebView area is a black box; surrounding Flutter UI is normal.',
            onTap: () => _push(
              context,
              const _MixedScreen(),
              'mixed_platform_view_masked',
            ),
          ),
          _CaseCard(
            title: 'Mixed screen — captured',
            subtitle:
                'Same screen, WebView wrapped with .capture — its content shows '
                'in replay instead of a black box.',
            onTap: () => _push(
              context,
              const _MixedScreenCapture(),
              'mixed_platform_view_captured',
            ),
          ),
          _CaseCard(
            title: 'Full screen — masked',
            subtitle:
                'WebView fills the screen (no surrounding Flutter). '
                'Entire area is a black box in replay.',
            onTap: () =>
                _push(context, const _FullScreenMasked(), 'fullscreen_masked'),
          ),
          _CaseCard(
            title: 'Full screen — captured',
            subtitle:
                'Full-screen WebView wrapped with .capture — the whole screen '
                'is revealed in replay.',
            onTap: () => _push(
              context,
              const _FullScreenCaptured(),
              'fullscreen_captured',
            ),
          ),
          _CaseCard(
            title: 'Two WebViews — both captured',
            subtitle:
                'Two WebViews side by side, both .capture — each shows its own '
                'content in replay.',
            onTap: () => _push(
              context,
              const _TwoCapturedWebViews(),
              'two_captured_webviews',
            ),
          ),
          _CaseCard(
            title: 'Two WebViews — one captured, one masked',
            subtitle:
                'Left WebView is .capture (revealed), right is default (black box). '
                'Verifies per-view policy.',
            onTap: () => _push(
              context,
              const _CapturedAndMaskedWebViews(),
              'mixed_capture_and_mask',
            ),
          ),
          _CaseCard(
            title: 'Per-view mask override',
            subtitle:
                'Left WebView is explicitly wrapped with '
                'PostHogPlatformView(privacy: .mask) — always a black box. '
                'Right has no wrapper — follows the global setting.',
            onTap: () => _push(
              context,
              const _ExplicitMaskGlobalFalse(),
              'per_view_mask_override',
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const SizedBox(height: 8),
            const Text(
              'Non-WebView platform view (Android)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _CaseCard(
              title: 'Map — masked',
              subtitle:
                  'GoogleMap in a Scaffold (hybrid-composition SurfaceView). '
                  'Map area is a black box in replay.',
              onTap: () => _push(
                context,
                const _GoogleMapsMixedScreen(),
                'google_maps_masked',
              ),
            ),
            _CaseCard(
              title: 'Map — captured',
              subtitle:
                  'GoogleMap wrapped with .capture — map content shows in replay.',
              onTap: () =>
                  _push(context, const _NonWebViewCapture(), 'map_captured'),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Out-of-engine native screens (captureNativeScreens)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _CaseCard(
            title: 'Native screen — captured (capture on)',
            subtitle:
                'Presents a fully native screen on top of Flutter. The native '
                'replay SDK snapshots it, so its content shows in replay.',
            onTap: () => _presentNativeScreen(capture: true),
          ),
          _CaseCard(
            title: 'Native screen — capture off',
            subtitle:
                'Same native screen with captureNativeScreens off — replay '
                'keeps showing the covered Flutter screen (previous behavior).',
            onTap: () => _presentNativeScreen(capture: false),
          ),
          if (defaultTargetPlatform == TargetPlatform.iOS)
            _CaseCard(
              title: 'Own-window native screen — captured (Superwall-style)',
              subtitle:
                  'Presented in a dedicated key UIWindow like Superwall, not '
                  'on the Flutter view controller. Verifies foreign-key-window '
                  'occlusion detection.',
              onTap: () => _presentNativeScreen(capture: true, ownWindow: true),
            ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen, String routeName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
        settings: RouteSettings(name: routeName),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CaseCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class _GoogleMapsMixedScreen extends StatefulWidget {
  const _GoogleMapsMixedScreen();

  @override
  State<_GoogleMapsMixedScreen> createState() => _GoogleMapsMixedScreenState();
}

class _GoogleMapsMixedScreenState extends State<_GoogleMapsMixedScreen> {
  static const _initialCamera = CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Maps in Scaffold')),
      body: Stack(
        children: [
          const GoogleMap(initialCameraPosition: _initialCamera),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search location…',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'List'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _MixedScreen extends StatefulWidget {
  const _MixedScreen();

  @override
  State<_MixedScreen> createState() => _MixedScreenState();
}

class _MixedScreenState extends State<_MixedScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.openstreetmap.org'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mixed: WebView (masked)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search location…',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'List'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _MixedScreenCapture extends StatefulWidget {
  const _MixedScreenCapture();

  @override
  State<_MixedScreenCapture> createState() => _MixedScreenCaptureState();
}

class _MixedScreenCaptureState extends State<_MixedScreenCapture> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.openstreetmap.org'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mixed: WebView (captured)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          PostHogPlatformView(
            privacy: PostHogPlatformViewPrivacy.capture,
            child: WebViewWidget(controller: _controller),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search location…',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'List'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _FullScreenMasked extends StatefulWidget {
  const _FullScreenMasked();

  @override
  State<_FullScreenMasked> createState() => _FullScreenMaskedState();
}

class _FullScreenMaskedState extends State<_FullScreenMasked> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://example.com'));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

class _FullScreenCaptured extends StatefulWidget {
  const _FullScreenCaptured();

  @override
  State<_FullScreenCaptured> createState() => _FullScreenCapturedState();
}

class _FullScreenCapturedState extends State<_FullScreenCaptured> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://example.com'));
  }

  @override
  Widget build(BuildContext context) {
    return PostHogPlatformView(
      privacy: PostHogPlatformViewPrivacy.capture,
      child: WebViewWidget(controller: _controller),
    );
  }
}

class _TwoCapturedWebViews extends StatefulWidget {
  const _TwoCapturedWebViews();

  @override
  State<_TwoCapturedWebViews> createState() => _TwoCapturedWebViewsState();
}

class _TwoCapturedWebViewsState extends State<_TwoCapturedWebViews> {
  late final WebViewController _left;
  late final WebViewController _right;

  @override
  void initState() {
    super.initState();
    _left = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://example.com'));
    _right = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.wikipedia.org'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two Captured WebViews')),
      body: Row(
        children: [
          Expanded(
            child: PostHogPlatformView(
              privacy: PostHogPlatformViewPrivacy.capture,
              child: WebViewWidget(controller: _left),
            ),
          ),
          Expanded(
            child: PostHogPlatformView(
              privacy: PostHogPlatformViewPrivacy.capture,
              child: WebViewWidget(controller: _right),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapturedAndMaskedWebViews extends StatefulWidget {
  const _CapturedAndMaskedWebViews();

  @override
  State<_CapturedAndMaskedWebViews> createState() =>
      _CapturedAndMaskedWebViewsState();
}

class _CapturedAndMaskedWebViewsState
    extends State<_CapturedAndMaskedWebViews> {
  late final WebViewController _left;
  late final WebViewController _right;

  @override
  void initState() {
    super.initState();
    _left = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://example.com'));
    _right = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.wikipedia.org'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Captured (left) + Masked (right)')),
      body: Row(
        children: [
          Expanded(
            child: PostHogPlatformView(
              privacy: PostHogPlatformViewPrivacy.capture,
              child: WebViewWidget(controller: _left),
            ),
          ),
          Expanded(
            child: PostHogPlatformView(
              privacy: PostHogPlatformViewPrivacy.mask,
              child: WebViewWidget(controller: _right),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplicitMaskGlobalFalse extends StatefulWidget {
  const _ExplicitMaskGlobalFalse();

  @override
  State<_ExplicitMaskGlobalFalse> createState() =>
      _ExplicitMaskGlobalFalseState();
}

class _ExplicitMaskGlobalFalseState extends State<_ExplicitMaskGlobalFalse> {
  late final WebViewController _left;
  late final WebViewController _right;

  @override
  void initState() {
    super.initState();
    _left = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://example.com'));
    _right = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://www.wikipedia.org'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Per-view mask override')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'LEFT: PostHogPlatformView(privacy: .mask) → always BLACK\n'
              'RIGHT: no wrapper → follows global maskAllPlatformViews '
              '(currently: $kMaskAllPlatformViews)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PostHogPlatformView(
                    privacy: PostHogPlatformViewPrivacy.mask,
                    child: WebViewWidget(controller: _left),
                  ),
                ),
                Expanded(child: WebViewWidget(controller: _right)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NonWebViewCapture extends StatefulWidget {
  const _NonWebViewCapture();

  @override
  State<_NonWebViewCapture> createState() => _NonWebViewCaptureState();
}

class _NonWebViewCaptureState extends State<_NonWebViewCapture> {
  static const _initialCamera = CameraPosition(
    target: LatLng(37.7749, -122.4194),
    zoom: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map — captured')),
      body: PostHogPlatformView(
        privacy: PostHogPlatformViewPrivacy.capture,
        child: const GoogleMap(initialCameraPosition: _initialCamera),
      ),
    );
  }
}
