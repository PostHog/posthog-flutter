Releasing
=========

Since `main` is protected, releases are done via pull requests.

 1. Choose a tag name (e.g. `3.0.0`), this is the version number of the release.
    1. Preview releases follow the pattern `3.0.0-alpha.1`, `3.0.0-beta.1`, `3.0.0-RC.1`
    2. Execute the script with the tag's name, the script will update the version file and create a release branch.

    ```bash
    ./scripts/prepare-release.sh 3.0.0
    ```
 2. Create a PR from the release branch to `main`
 3. Get approval and merge the PR
 4. Go to [GH Releases](https://github.com/PostHog/posthog-flutter/releases)
 5. Choose a tag name (e.g. `3.0.0`), same as step 2.
 6. Choose a release name (e.g. `3.0.0`), ideally it matches the above.
 7. Write a description of the release.
 8. Publish the release.
 9. GH Action (publish.yml) is doing everything else [automatically](https://pub.dev/packages/posthog_flutter/admin).
10. Done.
