# Releasing

This repository uses [Changesets](https://github.com/changesets/changesets) for version management and an automated GitHub Actions workflow for releases. It is a multi-package monorepo containing:

- **posthog_flutter** — Flutter plugin for iOS, Android, macOS, Web, Linux, and Windows
- **posthog_dart** — Pure Dart PostHog SDK (used by posthog_flutter on Linux/Windows)

## How to Release

### 1. Add a Changeset

When making changes that should be released, add a changeset:

```bash
pnpm changeset
```

This will prompt you to:
- Select the package(s) affected (posthog_flutter, posthog_dart, or both)
- Select the type of version bump (patch, minor, major) for each
- Write a summary of the changes

The changeset file will be created in the `.changeset/` directory.

### 2. Create a Pull Request

Create a PR with your changes and the changeset file(s).

### 3. Add the `release` Label

When the PR is ready to be released, add the `release` label to it.

### 4. Merge the PR

When the PR is merged to `main`, the release workflow will automatically:

1. Check for changesets
2. Notify the client libraries team in Slack for approval
3. Wait for approval from a maintainer (via GitHub environment protection)
4. Once approved:
   - Apply changesets and bump the version(s) for affected packages
   - Update the CHANGELOG.md for each released package
   - Sync versions to platform-specific files (pubspec.yaml, iOS, Android, version.dart)
   - Commit the version bump(s) to `main`
   - Create git tags and publish to pub.dev
   - Create GitHub releases

### Manual Trigger

You can also manually trigger the release workflow from the [Actions tab](https://github.com/PostHog/posthog-flutter/actions/workflows/publish.yml) by clicking "Run workflow".

## Version Bumping

Changesets handles version bumping automatically based on the changesets you create:

- **patch**: Bug fixes, documentation updates, internal changes (e.g., `5.15.0` → `5.15.1`)
- **minor**: New features, non-breaking changes (e.g., `5.15.0` → `5.16.0`)
- **major**: Breaking changes (e.g., `5.15.0` → `6.0.0`)

## Pre-release Versions

For pre-release versions (alpha, beta, RC), you can manually enter pre-release mode:

```bash
pnpm changeset pre enter alpha  # or beta, rc
pnpm changeset version
```

To exit pre-release mode:

```bash
pnpm changeset pre exit
```

## pub.dev Packages

- [`posthog_flutter`](https://pub.dev/packages/posthog_flutter)
- [`posthog_dart`](https://pub.dev/packages/posthog_dart)

## Tag Convention

- **posthog_flutter**: Tags use bare semver (e.g., `5.16.0`)
- **posthog_dart**: Tags use the prefix `posthog_dart@` (e.g., `posthog_dart@0.2.0`)

## Troubleshooting

### No changesets found

If the release workflow fails with "No changesets found", ensure your PR includes at least one changeset file in the `.changeset/` directory.

### Release not triggered

Make sure the PR has the `release` label applied before merging.

### Manual pub.dev publish (emergency only)

In case of automation failure, you can manually publish:

```bash
flutter pub get

# For posthog_flutter
cd posthog_flutter
flutter pub publish --force

# For posthog_dart
cd posthog_dart
dart pub publish --force
```

You'll need to be authenticated with pub.dev and have publish access to the packages.
