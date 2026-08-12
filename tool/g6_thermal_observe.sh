#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-}"
DURATION_MIN="${G6_DURATION_MIN:-15}"
OUT="${G6_OUT_DIR:-$ROOT/build/g6/thermal}"

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: set DEVICE=<flutter-device-id>" >&2
  flutter devices || true
  exit 2
fi
if ! [[ "$DURATION_MIN" =~ ^[0-9]+$ ]] || [[ "$DURATION_MIN" -lt 1 ]]; then
  echo "ERROR: G6_DURATION_MIN must be a positive integer" >&2
  exit 2
fi

mkdir -p "$OUT"
cd "$ROOT"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
log="$OUT/${stamp}-${DEVICE//[^A-Za-z0-9_.-]/_}.log"
start_epoch="$(date +%s)"
end_epoch=$((start_epoch + DURATION_MIN * 60))
cycle=0

{
  echo "PixelCraft G6.4 sustained workload"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "device=$DEVICE"
  echo "duration_min=$DURATION_MIN"
  echo "NOTE: thermal state/heat/throttling observations must still be recorded manually in docs/G6_RELIABILITY_MATRIX.md"
} | tee "$log"

while [[ "$(date +%s)" -lt "$end_epoch" ]]; do
  cycle=$((cycle + 1))
  echo "[G6.4] cycle=$cycle utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log"
  flutter test integration_test/performance_profile_test.dart -d "$DEVICE" 2>&1 \
    | tee -a "$log"
done

{
  echo "[G6.4] completed_cycles=$cycle"
  echo "[G6.4] evidence=$log"
} | tee -a "$log"
