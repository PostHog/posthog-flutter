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

### 3. Merge the PR

No release label is required. When the PR is merged to `main`, the release workflow will automatically:

1. Check for changesets
2. Notify the client libraries team in Slack for approval
3. Wait for the first approval from a maintainer (via GitHub `Release` environment protection)
4. Once approved:
   - Apply changesets and bump the version
   - Update the CHANGELOG.md
   - Sync the version to `pubspec.yaml`, iOS (`PostHogFlutterVersion.swift`), and Android (`PostHogVersion.kt`)
   - Commit the version bump to `main`
   - Create and push the release tag
5. The tag-triggered pub.dev publish workflow starts from that release tag
6. Wait for the second approval from a maintainer (via GitHub `Release` environment protection)
7. Once approved:
   - Publish the package to pub.dev
   - Create the GitHub release

Flutter releases require two `Release` environment approvals because pub.dev trusted publishing only allows publishing from GitHub tag workflows. The first approval gates the version bump and tag creation; the second approval gates the tag-triggered pub.dev publish job.

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

Release tags are protected by a GitHub tag ruleset: https://github.com/PostHog/posthog-flutter/settings/rules/11273241. This ensures tag-triggered pub.dev publishing can only happen from protected release tags created by the approved release process.

## Troubleshooting

### No changesets found

If the release workflow fails with "No changesets found", ensure your PR includes at least one changeset file in the `.changeset/` directory.

### Release not triggered

Make sure the PR includes a changeset file and was merged to `main`, or trigger the workflow manually from the Actions tab.

### Manual pub.dev publish (emergency only)

In case of automation failure, you can manually publish:

```bash
flutter pub get
cd posthog_flutter
flutter pub publish --force
```

You'll need to be authenticated with pub.dev and have publish access to the package.
