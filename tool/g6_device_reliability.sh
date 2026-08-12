#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-}"
CYCLES="${G6_CYCLES:-10}"
OUT="${G6_OUT_DIR:-$ROOT/build/g6/device}"

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: set DEVICE=<flutter-device-id>" >&2
  flutter devices || true
  exit 2
fi
if ! [[ "$CYCLES" =~ ^[0-9]+$ ]] || [[ "$CYCLES" -lt 1 ]]; then
  echo "ERROR: G6_CYCLES must be a positive integer" >&2
  exit 2
fi

mkdir -p "$OUT"
cd "$ROOT"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
summary="$OUT/${stamp}-${DEVICE//[^A-Za-z0-9_.-]/_}-summary.txt"

{
  echo "PixelCraft G6 device reliability"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "branch=$(git branch --show-current 2>/dev/null || echo unknown)"
  echo "device=$DEVICE"
  echo "cycles=$CYCLES"
  flutter devices
} | tee "$summary"

run_test() {
  local name="$1"
  shift
  local log="$OUT/${stamp}-${DEVICE//[^A-Za-z0-9_.-]/_}-${name}.log"
  echo "[G6] START $name" | tee -a "$summary"
  if "$@" 2>&1 | tee "$log"; then
    echo "[G6] PASS  $name" | tee -a "$summary"
  else
    local status=${PIPESTATUS[0]}
    echo "[G6] FAIL  $name status=$status log=$log" | tee -a "$summary"
    exit "$status"
  fi
}

run_test native_engine_smoke flutter test integration_test/native_engine_smoke_test.dart -d "$DEVICE"
run_test performance_profile flutter test integration_test/performance_profile_test.dart -d "$DEVICE"

for ((i=1; i<=CYCLES; i++)); do
  echo "[G6.2] soak cycle $i/$CYCLES" | tee -a "$summary"
  run_test "soak-${i}" flutter test integration_test/g6_reliability_soak_test.dart -d "$DEVICE"
done

# Keep the numeric lines in one compact file for later matrix transcription.
grep -hE 'PIXELCRAFT_(PROFILE|MEMORY|G6_)' "$OUT/${stamp}-${DEVICE//[^A-Za-z0-9_.-]/_}-"*.log \
  > "$OUT/${stamp}-${DEVICE//[^A-Za-z0-9_.-]/_}-metrics.txt" || true

echo "[G6] DEVICE RUN PASS evidence=$OUT" | tee -a "$summary"
