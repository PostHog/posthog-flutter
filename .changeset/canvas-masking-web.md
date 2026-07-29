---
"posthog_flutter": minor
---

**Session replay masking now works on Flutter web** ([#496](https://github.com/PostHog/posthog-flutter/issues/496)).

On Flutter web the app is painted into a single `<canvas>`, so DOM-based masking
could not see any of your text. Masking now applies inside the canvas:
`maskAllTexts`, `maskAllImages`, `PostHogMaskWidget` and obscured text fields all
mask canvas content, and Flutter's accessibility DOM is excluded from capture.

To enable it, add `maskRegionsFn` to `posthog.init` in your `web/index.html`:

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

The contract is fail-closed:

- Declaring `maskRegionsFn` is one of two ways to opt in — mounting a
  `PostHogMaskWidget` also switches canvas masking on (see the companion
  changeset). With neither, the plugin changes nothing.
- Your app must be wrapped in `PostHogWidget`; if the widget tree can't be
  walked, canvas frames are skipped instead of recorded unmasked, and a console
  warning explains the fix.
- Full DOM snapshots skip canvas pixel serialization while `maskRegionsFn` is
  configured, so they can't embed an unmasked screenshot of the app.
- On a posthog-js without `canvasCapture.maskRegionsFn` support (minimum version
  pinned at release) canvas frames are NOT masked — a console warning tells you
  to upgrade.

Caveats: web replay is configured in `posthog.init` (the Dart `sessionReplay`
flag drives iOS/Android only); list any project-level `blockSelector` in
`posthog.init` too, as the client-side selector takes precedence; DOM-rendered
platform views (`HtmlElementView`) follow posthog-js's DOM masking rules, not
canvas mask regions; on a page embedding multiple Flutter views, canvases
belonging to other Flutter views are skipped entirely (not recorded), since this
plugin's mask regions only describe its own view.

Also fixes `maskAllTexts: false` still masking `Text` widgets when
`maskAllImages` is on — this applies to iOS/Android screenshot masking too.
