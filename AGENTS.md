# Agent Instructions

- Read and follow [CONTRIBUTING.md](./CONTRIBUTING.md) before contributing to the SDK. It covers local checks, build checks, and testing against local native SDKs.
- Read and follow [RELEASING.md](./RELEASING.md) when adding changesets or working on publishing.
- Public API changes (a diff in `api/posthog_flutter.api.json`): if the author is a PostHog maintainer (git email ends in `@posthog.com`), the PR is the discussion, so don't open or suggest an issue. Otherwise, follow "Public API changes" in [CONTRIBUTING.md](./CONTRIBUTING.md): if there's no agreed issue, stop and tell the user. If a PR already exists, add a public-API note to its description and draft an issue body for the user to post. Never open an issue yourself. For SDK design guidance, read https://posthog.com/handbook/engineering/sdks/guidelines.md.
- Keep shared development guidance in `CONTRIBUTING.md` and release guidance in `RELEASING.md` rather than duplicating it here.
