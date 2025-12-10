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
if grep -q "^## $NEW_VERSION$" CHANGELOG.md; then
    # Version already exists, do nothing
    echo "Version '## $NEW_VERSION' already exists in CHANGELOG.md, skipping update"
elif grep -q "^## Next" CHANGELOG.md; then
    # Replace "## Next" with the new version
    perl -pi -e "s/^## Next$/## $NEW_VERSION/" CHANGELOG.md
    echo "Replaced '## Next' with '## $NEW_VERSION' in CHANGELOG.md"
else
    # If "## Next" doesn't exist and version doesn't exist, add the new version at the top of the file
    perl -i -pe "if (\$. == 1) {print \"## $NEW_VERSION\\n\\n\"}" CHANGELOG.md
    echo "Added '## $NEW_VERSION' at the top of CHANGELOG.md"
fi
