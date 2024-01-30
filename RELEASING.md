Releasing
=========

 1. Update the CHANGELOG.md with the version
 2. Choose a tag name (e.g. `3.0.0`), this is the version number of the release.
    1. Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
    2. Execute the script with the tag's name, the script will update the version file and create a tag.

    ```bash
    ./scripts/prepare-release.sh 3.0.0
    ```
 3. Go to [GH Releases](https://github.com/PostHog/posthog-flutter/releases)
 4. Choose a tag name (e.g. `3.0.0`), same as step 2.
 5. Choose a release name (e.g. `3.0.0`), ideally it matches the above.
 6. Write a description of the release.
 7. Publish the release.
 8. GH Action (publish.yml) is doing everything else [automatically](https://pub.dev/packages/posthog_flutter/admin).
 9. Done.
