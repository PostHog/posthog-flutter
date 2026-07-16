---
"posthog_flutter": patch
---

Raise the minimum `posthog-android` version to `3.54.1`. Earlier versions (e.g. `3.53.7`, which `5.30.0` resolved) copied the `MotionEvent` and submitted a task to the single-threaded replay executor on every Android touch, gating on the recording state only inside the submitted task. When `sessionReplay = false` (or the session is sampled out) this per-touch work still ran on the main thread and contended on the replay executor's work-queue lock, risking a Binder ANR. `3.54.1` checks the recording state before any allocation or executor submission, so touch dispatch does no replay work while replay is inactive.
