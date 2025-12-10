#!/bin/bash

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

# Check arguments
if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
    exit 1
fi

# Check if working directory is clean (ignore untracked files)
if [[ -n $(git diff --stat) ]] || [[ -n $(git diff --cached --stat) ]]; then
    error "Working directory is not clean. Please commit or stash your changes."
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (e.g., 1.2.3 or 1.2.3-alpha.1)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
    error "Invalid version format: $NEW_VERSION"
    echo "Version must match pattern: X.Y.Z or X.Y.Z-suffix (e.g., 1.2.3 or 1.2.3-alpha.1)"
    exit 1
fi

BRANCH_NAME="release/${NEW_VERSION}"

# ensure we're on main and up to date
git checkout main
git pull

# create release branch
git checkout -b "$BRANCH_NAME"

# bump version
./scripts/bump-version.sh $NEW_VERSION

# commit and push release branch
git commit -am "chore(release): bump to ${NEW_VERSION}"
git push -u origin "$BRANCH_NAME"

PR_URL="https://github.com/PostHog/posthog-flutter/compare/main...release%2F${NEW_VERSION}?expand=1"

echo ""
echo "Done! Created release branch: $BRANCH_NAME"
echo ""
echo "Next steps:"
echo "  1. Create a PR: $PR_URL"
echo "  2. Get approval and merge the PR"
echo "  3. Continue from step 4 on RELEASING.md"
