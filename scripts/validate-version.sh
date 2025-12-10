#!/bin/bash

# Validates a version string against semantic versioning format
# Usage: ./scripts/validate-version.sh <version>
# Returns: 0 if valid, 1 if invalid

set -e

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.2.3"
    echo "Example: $0 1.2.3-alpha.1"
    exit 1
fi

VERSION="$1"

# Validate version format (e.g., 1.2.3 or 1.2.3-alpha.1)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    echo "Error: Invalid version format: $VERSION" >&2
    echo "Version must match pattern: X.Y.Z or X.Y.Z-suffix (e.g., 1.2.3 or 1.2.3-alpha.1)" >&2
    exit 1
fi

echo "Version $VERSION is valid"
exit 0