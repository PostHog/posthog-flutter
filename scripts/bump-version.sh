#!/bin/bash

# ./scripts/bump-version.sh <package> <new version>
# eg ./scripts/bump-version.sh posthog_flutter "5.16.0"
# eg ./scripts/bump-version.sh posthog_dart "0.2.0"

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

PACKAGE="$1"
NEW_VERSION="$2"

if [ "$PACKAGE" = "posthog_flutter" ]; then
  # Replace iOS `postHogFlutterVersion` with the given version
  perl -pi -e "s/postHogFlutterVersion = \".*\"/postHogFlutterVersion = \"$NEW_VERSION\"/" posthog_flutter/ios/Classes/PostHogFlutterVersion.swift

  # Replace Android `postHogVersion` with the given version
  perl -pi -e "s/postHogVersion = \".*\"/postHogVersion = \"$NEW_VERSION\"/" posthog_flutter/android/src/main/kotlin/com/posthog/flutter/PostHogVersion.kt

  # Replace Flutter `version` with the given version
  perl -pi -e "s/^version: .*/version: $NEW_VERSION/" posthog_flutter/pubspec.yaml

  # Update posthog_dart dependency from path to version constraint for publishing
  # Get the current posthog_dart version
  DART_VERSION=$(grep '^version:' posthog_dart/pubspec.yaml | sed 's/version: //')
  # Replace the path dependency block with a version dependency
  # The pubspec has:
  #   posthog_dart:
  #     path: ../posthog_dart
  # Replace with:
  #   posthog_dart: ^<version>
  perl -0pi -e "s/  posthog_dart:\n    path: ..\/posthog_dart/  posthog_dart: ^$DART_VERSION/" posthog_flutter/pubspec.yaml
elif [ "$PACKAGE" = "posthog_dart" ]; then
  # Replace Dart `version` with the given version in pubspec.yaml
  perl -pi -e "s/^version: .*/version: $NEW_VERSION/" posthog_dart/pubspec.yaml

  # Replace Dart `sdkVersion` with the given version in version.dart
  perl -pi -e "s/sdkVersion = '.*'/sdkVersion = '$NEW_VERSION'/" posthog_dart/lib/src/version.dart
else
  echo "Unknown package: $PACKAGE"
  echo "Usage: $0 <posthog_flutter|posthog_dart> <version>"
  exit 1
fi
