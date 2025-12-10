#!/bin/bash

# ./scripts/bump-version.sh <new version>
# eg ./scripts/bump-version.sh "3.0.0-alpha.1"

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

NEW_VERSION="$1"

# Replace iOS `postHogFlutterVersion` with the given version
perl -pi -e "s/postHogFlutterVersion = \".*\"/postHogFlutterVersion = \"$NEW_VERSION\"/" ios/Classes/PostHogFlutterVersion.swift

# Replace Android `postHogVersion` with the given version
perl -pi -e "s/postHogVersion = \".*\"/postHogVersion = \"$NEW_VERSION\"/" android/src/main/kotlin/com/posthog/flutter/PostHogVersion.kt

# Replace Flutter `version` with the given version
perl -pi -e "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml

# Update CHANGELOG.md
echo "Updating CHANGELOG.md..."
if grep -q "^## Next" CHANGELOG.md; then
    # Replace "## Next" with the new version
    perl -pi -e "s/^## Next$/## $NEW_VERSION/" CHANGELOG.md
    echo "Replaced '## Next' with '## $NEW_VERSION' in CHANGELOG.md"
else
    # If "## Next" doesn't exist, add the new version at the top of the file
    # Create a temporary file with the new content
    echo "## $NEW_VERSION" > CHANGELOG.md.tmp
    echo "" >> CHANGELOG.md.tmp
    cat CHANGELOG.md >> CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
    echo "Added '## $NEW_VERSION' at the top of CHANGELOG.md"
fi
