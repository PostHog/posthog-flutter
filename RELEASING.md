# Automated Release Process

This repository uses GitHub Actions to automate the release process. The workflow ensures that all version updates and changelog modifications are completed before creating the release tag.

## How It Works

The release process is split into two workflows:

### 1. Prepare Release Workflow (`prepare-release.yml`)
- Triggered manually via GitHub Actions UI with a version input
- Creates a release branch
- Updates version in all necessary files (pubspec.yaml, iOS, Android)
- Updates CHANGELOG.md (replaces `## Next` with the version or adds it at the top)
- Creates a Pull Request to main

### 2. Tag Release Workflow (`tag-release.yml`)
- Automatically triggered when a release PR is merged to main
- Creates a git tag with the version
- Creates a GitHub Release with auto-generated release notes

## Release Steps

### Step 1: Prepare Your Changes
1. Ensure all your changes are merged to main
2. Update CHANGELOG.md with release notes under `## Next` section (optional - if not present, version will be added at the top)

### Step 2: Trigger the Release
1. Go to Actions tab in GitHub
2. Select "Prepare Release" workflow
3. Click "Run workflow"
4. Enter the version number (e.g., `5.10.0` or `5.10.0-beta.1`)
5. Click "Run workflow"

### Step 3: Review and Merge
1. The workflow will create a PR with all version updates
2. Review the changes
3. Approve and merge the PR

### Step 4: Automatic Tag Creation
1. Once the PR is merged, the tag-release workflow automatically:
   - Creates a git tag (e.g., `v5.10.0`)
   - Creates a GitHub Release with release notes

## Version Format

The version must follow semantic versioning:
- Format: `X.Y.Z` or `X.Y.Z-suffix`
- Examples: `1.2.3`, `2.0.0-alpha.1`, `3.1.0-beta.2`
