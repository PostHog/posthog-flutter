import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
            'Test cases for maskAllPlatformViews',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Session replay is enabled with maskAllPlatformViews = true (default).\n'
            'Platform view areas are auto-masked (black box). Wrap a view with\n'
            'PostHogPlatformView(privacy: .capture) to reveal it instead.',
          ),
          const SizedBox(height: 24),
          if (defaultTargetPlatform == TargetPlatform.android)
            _CaseCard(
              title: '1. google_maps_flutter in Scaffold',
              subtitle:
                  'GoogleMap embedded in a Scaffold with app bar and bottom nav. '
                  'The exact use-case from the PR comments. '
                  'Uses hybrid-composition SurfaceView.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _GoogleMapsMixedScreen(),
                  settings: const RouteSettings(name: 'google_maps_platform_view'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _CaseCard(
            title: '2. Mixed screen (WebView)',
            subtitle:
                'WebView embedded in a Scaffold with app bar, '
                'search overlay, and bottom nav. '
                'Texture-mode platform view (RenderAndroidView).',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _MixedScreen(),
                settings: const RouteSettings(name: 'mixed_platform_view'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CaseCard(
            title: '3. Full-screen native view',
            subtitle:
                'WebView fills the entire screen — no surrounding Flutter UI. '
                'Represents a full-screen paywall or native map.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _FullScreenNativeView(),
                settings:
                    const RouteSettings(name: 'fullscreen_platform_view'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CaseCard(
            title: '4. Mixed screen (WebView, captured)',
            subtitle:
                'WebView wrapped with PostHogPlatformView(privacy: .capture). '
                'Should show WebView content in replay instead of a black box '
                '(Phase 2 per-view override).',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _MixedScreenCapture(),
                settings:
                    const RouteSettings(name: 'mixed_platform_view_capture'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CaseCard(
            title: '5. Two WebViews, both captured',
            subtitle:
                'Two WebViews side by side, each wrapped with capture policy. '
                'Both should show their content independently in replay.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _TwoCapturedWebViews(),
                settings: const RouteSettings(name: 'two_captured_webviews'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (defaultTargetPlatform == TargetPlatform.android)
            _CaseCard(
              title: '6. Non-WebView platform view, capture policy',
              subtitle:
                  'GoogleMap wrapped with capture policy. On Android the map '
                  'content should be visible; on iOS it falls back to mask.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _NonWebViewCapture(),
                  settings:
                      const RouteSettings(name: 'non_webview_capture'),
                ),
              ),
            ),
        ],
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

// ---------------------------------------------------------------------------
// Google Maps mixed screen: the exact use-case from the PR comments.
// GoogleMap (hybrid-composition SurfaceView) inside a Scaffold.
// API key is intentionally invalid — we test capture/mask, not map tiles.
// ---------------------------------------------------------------------------

class _GoogleMapsMixedScreen extends StatefulWidget {
  const _GoogleMapsMixedScreen();

  @override
  State<_GoogleMapsMixedScreen> createState() => _GoogleMapsMixedScreenState();
}

class _GoogleMapsMixedScreenState extends State<_GoogleMapsMixedScreen> {
  static const _initialCamera = CameraPosition(
    target: LatLng(37.7749, -122.4194), // San Francisco
    zoom: 12,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps in Scaffold'),
      ),
      body: Stack(
        children: [
          // The real google_maps_flutter platform view.
          // With an invalid API key it shows grey/error tiles but the
          // SurfaceView is present in the hierarchy — that is what we test.
          const GoogleMap(
            initialCameraPosition: _initialCamera,
          ),

          // Flutter overlay on top of the map — simulates a search bar.
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

// ---------------------------------------------------------------------------
// Mixed screen: Flutter Scaffold + embedded WebView + Flutter overlays
// ---------------------------------------------------------------------------

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
        title: const Text('Mixed: Map in Scaffold'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // The platform view (WebView / native map)
          WebViewWidget(controller: _controller),

          // Flutter overlay on top of the platform view — simulates a search
          // bar or FAB rendered over a map. This Flutter content should be
          // visible in session replay; the WebView underneath is auto-masked.
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

          // FAB-style Flutter button over the map
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

// ---------------------------------------------------------------------------
// Mixed screen (captured): same as _MixedScreen but wrapped in
// PostHogPlatformView(privacy: .capture) — should reveal WebView in replay.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Full-screen native view: WebView fills the entire screen
// ---------------------------------------------------------------------------

class _FullScreenNativeView extends StatefulWidget {
  const _FullScreenNativeView();

  @override
  State<_FullScreenNativeView> createState() => _FullScreenNativeViewState();
}

class _FullScreenNativeViewState extends State<_FullScreenNativeView> {
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

// ---------------------------------------------------------------------------
// Two captured WebViews: tests multiple platform views with capture policy
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Non-WebView capture: GoogleMap wrapped with capture policy.
// Android: map content visible. iOS: no WKWebView → falls back to mask.
// ---------------------------------------------------------------------------

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
      appBar: AppBar(title: const Text('Non-WebView (capture policy)')),
      body: PostHogPlatformView(
        privacy: PostHogPlatformViewPrivacy.capture,
        child: const GoogleMap(initialCameraPosition: _initialCamera),
      ),
    );
  }
}
