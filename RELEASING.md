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

Make sure the PR includes a changeset file and was merged to `main`, or trigger the workflow manually from the Actions tab.

### Failed or cancelled release

The independent [release failure notification workflow](.github/workflows/release-failure-notification.yml) checks every completed main-branch Release attempt and every completed [Publish to pub.dev](.github/workflows/publish-pub-dev.yml) attempt, and alerts if a job failed, timed out, or was cancelled. It also alerts when a run failed but its expected job never ran (the version bump, commit, and tag job, or the pub.dev publish job), which happens when GitHub Actions stops mid-run. Once the package is on pub.dev, alerts describe follow-up problems rather than claiming the release failed. The workflow still alerts if the package is published but the Slack step in the released notification job was skipped. It only acts on runs that a push or a manual dispatch started in this repository.

Cancelled runs with no jobs are ignored, including superseded queued runs and manual cancellations before any job is created. A version-bump failure before any steps ran is also ignored when the rejection-reply step confirms an explicit rejection in the same attempt and no other job failed.

Job inspection retries transient GitHub API failures up to three times. If inspection still fails, it logs the HTTP status or error type and message, then posts a fallback alert with the overall run status and logs link so the release can be checked manually. Error diagnostics stay in the run log, not in the Slack message.

Alerts for the Release workflow reply to the approval thread in the release approvals Slack channel. The release workflow preserves the thread timestamp in a run artifact for 30 days, independently of release approval. Failed-job reruns reuse the latest available thread from the same or an earlier attempt. If the timestamp is missing, invalid, or unavailable, or the failed run is a pub.dev publish, the alert falls back to a new channel message. The completion workflow must be present on the default branch to run.

### Manual pub.dev publish (emergency only)

In case of automation failure, you can manually publish:

```bash
flutter pub get
cd posthog_flutter
flutter pub publish --force
```

You'll need to be authenticated with pub.dev and have publish access to the package.
