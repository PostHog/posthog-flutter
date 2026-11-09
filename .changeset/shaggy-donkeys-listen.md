---
'posthog_flutter': patch
---

Keep Android surveys working when `setup()` runs more than once in a process, for example after a Flutter hot restart. The plugin now reuses the survey delegate that the native SDK holds, and points it at the engine that is attached, so a survey that appears captures `survey shown`, `survey sent` and `survey dismissed` again, keeps the answer, and counts as seen. A recurring survey no longer comes back on every launch. Release the delegate's channel when its engine detaches, and discard the delegate when the SDK closes. Preserve unfinished answers across engine detach/reattach without recording a dismissal.
