Releasing
=========

 1. Update the CHANGELOG.md with the version
 2. Go to [GH Releases](https://github.com/PostHog/posthog-android/releases)
 3. Choose a tag name (e.g. `3.0.0`), this is the version number of the release (the tag must follow this format).
     1. Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
 4. Choose a release name (e.g. `3.0.0`), ideally it matches the above.
 5. Write a description of the release.
 6. Publish the release.
 7. GH Action (publish.yml) is doing everything else [automatically](https://pub.dev/packages/posthog_flutter/admin).
 8. Done.
