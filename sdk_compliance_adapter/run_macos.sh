#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKSPACE=${1:?Usage: run_macos.sh WORKSPACE HARNESS_CHECKOUT REPORT_DIRECTORY}
HARNESS=${2:?Provide an unchanged harness checkout}
REPORT=${3:?Provide a report directory}
PYTHON=${PYTHON:-python3}
WORKSPACE=$(cd "$WORKSPACE" && pwd)
HARNESS=$(cd "$HARNESS" && pwd)
mkdir -p "$REPORT"
REPORT=$(cd "$REPORT" && pwd)
PORT=${PORT:-18310}
MOCK_PORT=${MOCK_PORT:-19310}
PROXY_PORT=${PROXY_PORT:-19311}
APP_PORT=${APP_PORT:-18311}
for port in "$PORT" "$APP_PORT" "$MOCK_PORT" "$PROXY_PORT"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN; then
    echo "Port $port is already occupied" >&2
    exit 1
  fi
done
cp "$WORKSPACE/runner/macos/Podfile.lock" "$REPORT/Podfile.lock"
cp "$WORKSPACE/pubspec.lock" "$REPORT/pubspec.lock"
cp "$WORKSPACE/toolchain.txt" "$WORKSPACE/delegate-versions.txt" "$REPORT/"
git -C "$HARNESS" rev-parse HEAD > "$REPORT/harness-ref.txt"
printf 'native Python harness; macOS Flutter release app; fresh home per init\n' > "$REPORT/execution-mode.txt"
"$PYTHON" "$ROOT/sdk_compliance_adapter/macos_controller.py" \
  "$WORKSPACE/runner/build/macos/Build/Products/Release/flutter_compliance.app/Contents/MacOS/flutter_compliance" \
  "$REPORT" --port "$PORT" --app-port "$APP_PORT" --proxy-port "$PROXY_PORT" \
  > "$REPORT/controller.log" 2>&1 &
ADAPTER_PID=$!
trap 'kill "$ADAPTER_PID" 2>/dev/null || true; wait "$ADAPTER_PID" 2>/dev/null || true' EXIT
ready=false
for attempt in {1..60}; do
  if curl -fsS "http://127.0.0.1:$PORT/health" > "$REPORT/health.json"; then
    ready=true
    break
  fi
  kill -0 "$ADAPTER_PID"
  sleep 1
done
$ready
cd "$HARNESS"
export PYTHONPATH="$HARNESS/src${PYTHONPATH:+:$PYTHONPATH}"
"$PYTHON" -m posthog_test_harness.cli run \
  --adapter-url "http://127.0.0.1:$PORT" \
  --mock-port "$MOCK_PORT" --mock-url "http://127.0.0.1:$MOCK_PORT" \
  --sdk-type server --concurrency 1 --output text \
  --report "$REPORT/report.json" 2>&1 | tee "$REPORT/harness.log"
