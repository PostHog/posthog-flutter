---
'posthog_flutter': patch
---

Fix session replay masking only the first line of an auto-growing text field (`maxLines: null` or `expands: true`); the mask now covers the field's full height.
