---
"posthog_flutter": minor
---

**`PostHogMaskWidget` now works on Flutter web without any HTML setup.**

Wrapping a widget in `PostHogMaskWidget` is the most explicit way to say "never
record this", so on web the first one to mount now switches canvas masking on by
itself — no `maskRegionsFn` in `posthog.init` required. `PostHogMaskWidget`
therefore behaves the same on web as it does on iOS and Android.

Things to know:
- Mounting one `PostHogMaskWidget` enables your whole masking configuration, not
  just the wrapped subtree: `maskAllTexts` and `maskAllImages` default to true, so
  a single mask widget turns on full text and image canvas masking — the same
  semantics as mounting one on iOS and Android.
- Switching masking on restarts an in-flight recording once, because masking also
  excludes the Flutter semantics DOM tree via `blockSelector`, which posthog-js only
  reads when recording starts. You will see the recording split at that point.
- Frames captured before the first `PostHogMaskWidget` mounts are recorded unmasked,
  and full snapshots taken in that window can likewise embed unmasked canvas stills
  (`rr_dataURL`). Declaring `maskRegionsFn: () => null` in `posthog.init` is still
  the only way to cover the window between page load and Flutter booting, and it
  moves the restart to Flutter boot rather than to whenever your first
  `PostHogMaskWidget` mounts.
- Your app must be wrapped in `PostHogWidget`. If it is not, canvas frames are
  skipped instead of recorded unmasked, and a console warning explains the fix.

Apps that declare neither are untouched, exactly as before.
