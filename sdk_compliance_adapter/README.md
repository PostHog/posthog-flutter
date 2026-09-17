# Flutter macOS compliance profile

This adapter runs a **real macOS Flutter application**. Calls go through the
public `Posthog` Dart facade, the shipped MethodChannel implementation and the
registered Apple plugin. The resolved PostHog CocoaPod owns event construction,
UUIDs, timestamps, batching, compression, retries, flag parsing and flag-called
events. This profile does not certify Android, iOS devices/simulators or web.

## Run

Requires macOS, Xcode, CocoaPods, Flutter **3.44.0** (Dart 3.12), and an unchanged
[SDK harness](https://github.com/PostHog/posthog-sdk-test-harness) checkout with
its Python dependencies installed. CI pins the native harness source to release
**1.0.0**, `6d19abb9c81e2262dacbe340e7dddda9c871c178`, rather than requiring Docker
on the macOS runner.

From the repository root, using new, absolute output directories:

```sh
bash sdk_compliance_adapter/build_macos.sh /tmp/flutter-compliance-build
bash sdk_compliance_adapter/run_macos.sh \
  /tmp/flutter-compliance-build /path/to/posthog-sdk-test-harness \
  /tmp/flutter-compliance-report
python3 sdk_compliance_adapter/check_report.py /tmp/flutter-compliance-report/report.json
```

`PYTHON` can select the harness virtualenv interpreter. `PORT`, `MOCK_PORT` and
`PROXY_PORT` default to 18310, 19310 and 19311. `APP_PORT` defaults to 18311.
Observer unit tests use 19312/19313; the native regression also uses 18312/18313.
The runner checks for occupied service ports and cleans up its owned processes.

The build script creates an isolated workspace containing unmodified SDK sources
and manifests, the adapter and a generated macOS runner. It does not build the
example or relax SDK dependency constraints. CocoaPods metadata is isolated too.
The generated app disables automatic initialization and the app sandbox; it is
only a local test controller, not an app distribution template.

Reports include Flutter/Dart versions, wrapper version, **resolved** Apple
version, `Podfile.lock`, Dart lockfile, harness revision, health, and logs. The
initial validated combination is Flutter 3.44.0 / wrapper 5.39.0 / Apple 3.71.6;
subsequent builds resolve within the SDK's unchanged native dependency range.

## Mapping and observation limits

- The Python HTTP controller starts the real Flutter binary with a fresh owned
  `CFFIXED_USER_HOME`, `HOME` and `TMPDIR` for every `/init`. `/reset` terminates
  that app, waits for exit, and removes only its whole temporary environment.
  Native SDK reset intentionally preserves queued events, so it cannot isolate
  harness cases. This profile tests process isolation, not native reset semantics.
- `/init` forwards host, `flush_at` and `flush_interval_ms`. Application lifecycle
  capture and startup flag preload are explicitly disabled. Flag-called events
  retain their SDK default. Native configuration serialization, including
  whole-second interval precision, is unchanged. The adapter's default interval
  is one second, the smallest positive interval supported by the Apple bridge.
- Capture identity changes use public `identify`; flags use public identity,
  person/group setters, awaited `reloadFeatureFlags` and cached `getFeatureFlag`.
  `force_remote: false` omits the explicit reload, not any setter-triggered work.
  **Identify/group events and automatic reloads are preserved.** This can affect
  event counts and consume mock responses before the requested capture/reload.
  Reload-per-action is not a claim about ordinary cached getter network behavior.
- There is no public Flutter timestamp override, returned capture UUID, analytics
  retry-budget/compression switch, queue state or per-getter GeoIP/singleton scope
  control. Timestamp requests return HTTP 501; capture UUID and flush counts are
  `null`; `/state` returns HTTP 501. Unsupported configuration is not synthesized.
- A loopback proxy forwards each request and response once, preserving body bytes,
  headers (except transport hop headers), response codes and retry headers. It
  never retries. Per-initialization URL prefixes isolate late requests from closed
  SDK instances; the prefix is removed when forwarding to the mock host.
- `/flush` calls public flush **once** and waits up to 30 seconds for submitted
  capture names to be observed under SDK-generated UUIDs with terminal HTTP
  responses, no observed outstanding batches, and one second of network quiet.
  Unobserved captures, unresolved retry batches and observation errors fail the
  action explicitly. With no submitted captures, the action returns HTTP 501
  after invoking public flush: network silence cannot prove an empty queue or
  automatic-event completion. This is a bounded capture-wire observation,
  **not a native queue drain guarantee**. Automatic SDK events and permanently
  exhausted retries have no public completion callback. No timer or flush loop
  drives SDK retries. `/observations` exposes passive request records, not SDK
  queue state.

## Selected coverage

`expected-tests.json` lists all **47** selected contract 1.2 definitions:
30 server-wire capture and 17 flags cases, with `capture_v0` and `encoding_gzip`.
No individual failures are filtered. CI keeps assertion failures advisory but
fails on missing, duplicate, unexpected or zero-case reports.

The supported first-pass targets are 29 capture cases (excluding the absent
explicit timestamp override), flag wire fields/path, groups, returned values,
502/504 retries, flag-called events, and explicit reload-per-action. Results can
still fail because of real SDK policy, identity side effects, mock response
routing, or bounded flush observation; a passing status test is not sufficient
proof of capture retry behavior if another SDK request consumed its mock status.

Deferred assertions remain visible in the full report: timestamp override,
compound person/default-empty-group payloads, GeoIP, singleton key scope and
native-default preload lifecycle. Apple omits fields some server-oriented flags
assertions require. Web flags/gzip applicability, other platforms, V1/AI,
alternate codecs and exact native queue-drain/state contracts remain uncovered.

The resolved Apple 3.71.6 parser requires both `featureFlags` and
`featureFlagPayloads` maps; legacy-only harness fixtures can therefore return
`null` through the real getter. The harness fixtures are unchanged. A separate
native regression uses a compatible mock response to verify public reload/getter
502/504 retries and SDK-generated flag-called events. It also verifies reset
isolation with an unsent event and native capture 503-to-200 retry identity. These
focused checks run against the built app as a build gate, separately from the
advisory 47-case harness inventory.
