# posthog_flutter_example

Demonstrates how to use the posthog_flutter plugin.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Running web example

```bash
# release mode
rm -rf build/web
flutter build web --source-maps
posthog-cli sourcemap inject --directory build/web
# check the sourcemaps has chunk_id and release_id injected (*.js.map file)
# check the js file has _posthogChunkIds injected (*.js file)
# check the chunk_id and _posthogChunkIds match
posthog-cli sourcemap upload --directory build/web
cd build/web
# https://pub.dev/packages/dhttpd
dhttpd
```