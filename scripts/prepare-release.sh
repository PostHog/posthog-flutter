#!/bin/bash

set -eux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR/..

NEW_VERSION="$1"
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

PR_URL="https://github.com/PostHog/posthog-android/compare/main...release%2F${NEW_VERSION}?expand=1"

echo ""
echo "Done! Created release branch: $BRANCH_NAME"
echo ""
echo "Next steps:"
echo "  1. Create a PR: $PR_URL"
echo "  2. Get approval and merge the PR"
echo "  3. Continue from step 5 on RELEASING.md"
