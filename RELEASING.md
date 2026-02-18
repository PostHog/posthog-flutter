# Releasing

This repository uses [Changesets](https://github.com/changesets/changesets) for version management and an automated GitHub Actions workflow for releases.

## How to Release

### 1. Add a Changeset

When making changes that should be released, add a changeset:

```bash
pnpm changeset
```

This will prompt you to:
- Select the type of version bump (patch, minor, major)
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
   - Apply changesets and bump the version
   - Update the CHANGELOG.md
   - Sync the version to `pubspec.yaml`, iOS (`PostHogFlutterVersion.swift`), and Android (`PostHogVersion.kt`)
   - Commit the version bump to `main`
   - Publish the package to pub.dev
   - Create a git tag and GitHub release

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

## pub.dev Package

The package is published as [`posthog_flutter`](https://pub.dev/packages/posthog_flutter) on pub.dev.

## Troubleshooting

### No changesets found

If the release workflow fails with "No changesets found", ensure your PR includes at least one changeset file in the `.changeset/` directory.

### Release not triggered

Make sure the PR has the `release` label applied before merging.

### Manual pub.dev publish (emergency only)

In case of automation failure, you can manually publish:

```bash
flutter pub get
flutter pub publish --force
```

You'll need to be authenticated with pub.dev and have publish access to the package.
