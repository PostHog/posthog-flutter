---
'posthog_flutter': minor
---

Add the `disableGeoip` config so an app can opt out of server-side GeoIP enrichment. When enabled, events carry `$geoip_disable: true` and feature flag requests send `geoip_disable: true`, so the server doesn't infer the user's location from their IP address. Android requires posthog-android 3.77.0 or later. Flutter web doesn't apply it; set `$geoip_disable` in your posthog-js `before_send` instead.
