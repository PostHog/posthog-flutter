#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
SNAPSHOT_FILE="$ROOT_DIR/api/posthog_flutter.api.json"
UPDATE=false

while (( "$#" )); do
  key="$1"
  shift
  case "$key" in
    -u|--update)
      UPDATE=true
      ;;
    -\?|-h|--help)
      cat <<'EOF'
Usage: scripts/check-api-dart.sh [--update]

Checks the posthog_flutter public Dart API against api/posthog_flutter.api.json.
Use --update after intentional public API changes.
EOF
      exit
      ;;
    *)
      echo "Unknown option: $key" >&2
      exit 1
      ;;
  esac
done

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

RAW_API="$TMP_DIR/posthog_flutter.raw.api.json"
GENERATED_API="$TMP_DIR/posthog_flutter.api.json"

cd "$ROOT_DIR/posthog_flutter"
dart run dart_apitool:main extract \
  --input . \
  --output "$RAW_API" \
  --force-use-flutter

python3 - "$RAW_API" "$GENERATED_API" <<'PY'
import json
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
data = json.loads(raw_path.read_text())
# dart_apitool writes a temporary package path that changes on every run.
data.get("packageApi", {}).pop("packagePath", None)
out_path.write_text(json.dumps(data, indent=4, sort_keys=True) + "\n")
PY

if $UPDATE; then
  mkdir -p "$(dirname "$SNAPSHOT_FILE")"
  cp "$GENERATED_API" "$SNAPSHOT_FILE"
  echo "Updated $SNAPSHOT_FILE"
  exit
fi

if [[ ! -f "$SNAPSHOT_FILE" ]]; then
  echo "Missing public API snapshot: $SNAPSHOT_FILE" >&2
  echo "Run scripts/check-api-dart.sh --update to create it." >&2
  exit 1
fi

if diff -u "$SNAPSHOT_FILE" "$GENERATED_API"; then
  echo "posthog_flutter public API snapshot is up to date."
else
  echo "posthog_flutter public API changed. Run scripts/check-api-dart.sh --update if intentional." >&2
  exit 1
fi
