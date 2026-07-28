---
"posthog_flutter": minor
---

**Session replay masking now works on Flutter web** ([#496](https://github.com/PostHog/posthog-flutter/issues/496)).

On Flutter web your app is painted into a single `<canvas>`, so PostHog's DOM-based
masking could not see any of your text — session recordings captured it in the clear
even if you had masking configured. Masking now applies inside the canvas.

To enable it, add `maskRegionsFn` to the `posthog.init` call in your
`web/index.html`:

```js
posthog.init('<your-token>', {
  session_recording: {
    captureCanvas: {
      recordCanvas: true,
    },
    canvasCapture: {
      // the plugin replaces this once Flutter has started; until then
      // frames are skipped rather than recorded unmasked
      maskRegionsFn: () => null,
    },
  },
})
```

Once enabled, `sessionReplayConfig.maskAllTexts`, `maskAllImages`,
`PostHogMaskWidget` and obscured text fields all mask canvas content, and Flutter's
accessibility tree is excluded from DOM capture so your text is not recorded through
it either.

Notes:

- If you leave `maskRegionsFn` out, the plugin changes nothing and recording
  behaves exactly as posthog-js is configured — as it did before this release.
  **This includes `PostHogMaskWidget`**: on web it has no effect unless
  `maskRegionsFn` is declared, because the canvas is masked by posthog-js and
  the plugin only supplies rectangles to it once you have opted in. On iOS and
  Android `PostHogMaskWidget` continues to work with no extra setup.
  If canvas recording is enabled in your project settings rather than in
  `posthog.init`, the plugin cannot detect it and will not warn.
- Web replay is configured entirely in `posthog.init`. The `config.sessionReplay`
  Dart flag drives iOS/Android screenshot capture only and does not affect what
  is recorded on web.
- When you opt in, the plugin adds `flt-semantics-host` to
  `session_recording.blockSelector` so Flutter's accessibility tree is not recorded
  as plaintext. A client-side `blockSelector` takes precedence over the one in your
  project's Privacy and masking settings, so if you rely on a project-level selector,
  list it in `posthog.init` as well — the plugin merges with what is there and cannot
  see the project-level value. posthog-js may also log a notice about `blockSelector`
  in `posthog.init` for this reason.
- rrweb's DOM full snapshot serializes 2D-context canvases inline (`rr_dataURL`)
  without applying mask regions. Flutter's CanvasKit renderer draws to WebGL, which
  that path does not serialize, so your Flutter canvas is not exposed through it —
  but keep it in mind if your page contains additional 2D canvases of its own.
- Widgets rendered as DOM rather than canvas pixels — `HtmlElementView`-based platform
  views such as maps, webviews and iframes — are recorded as DOM and masked by
  posthog-js's DOM rules, not by canvas mask regions. `PostHogMaskWidget` around a
  platform view does not mask it on web.
- Your app must be wrapped in `PostHogWidget`. If it is not, canvas frames are
  skipped instead of recorded unmasked, and a console warning explains the fix.
- Requires a posthog-js version that supports `canvasCapture.maskRegionsFn`.
