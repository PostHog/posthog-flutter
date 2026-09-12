#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKSPACE=${1:?Usage: build_macos.sh NEW_WORKSPACE_DIRECTORY}
python3 "$ROOT/sdk_compliance_adapter/prepare_macos.py" "$WORKSPACE"
WORKSPACE=$(cd "$WORKSPACE" && pwd)
export CP_HOME_DIR="$WORKSPACE/.cocoapods"
export COCOAPODS_DISABLE_STATS=true
cd "$WORKSPACE"
flutter --version > toolchain.txt
flutter pub get
# Refresh only this build's CocoaPods metadata, not the developer's shared repo.
pod repo add-cdn trunk https://cdn.cocoapods.org/
pod repo update
cd sdk_compliance_adapter
flutter test test/wire_observer_test.dart
dart analyze lib test
cd ../runner
flutter build macos --release --config-only
SDK_VERSION=$(sed -n 's/^version: //p' ../posthog_flutter/pubspec.yaml)
DELEGATE_VERSION=$(sed -n 's/^  - PostHog (\([^)]*\)).*/\1/p' macos/Podfile.lock)
test -n "$SDK_VERSION"
test -n "$DELEGATE_VERSION"
printf 'Flutter wrapper: %s\nApple delegate (CocoaPods): %s\n' "$SDK_VERSION" "$DELEGATE_VERSION" > ../delegate-versions.txt
flutter build macos --release \
  --dart-define="SDK_VERSION=$SDK_VERSION" \
  --dart-define="DELEGATE_VERSION=$DELEGATE_VERSION"
FLUTTER_COMPLIANCE_BINARY="$PWD/build/macos/Build/Products/Release/flutter_compliance.app/Contents/MacOS/flutter_compliance" \
  TEST_OUTPUT="$WORKSPACE" python3 "$ROOT/sdk_compliance_adapter/test_native_runtime.py" -v
