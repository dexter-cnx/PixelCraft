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
safe_device="${DEVICE//[^A-Za-z0-9_.-]/_}"
log="$OUT/${stamp}-${safe_device}.log"

{
  echo "PixelCraft G6.4 sustained workload"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "device=$DEVICE"
  echo "duration_min=$DURATION_MIN"
  echo "session=single flutter drive"
  echo "main_app_policy=do not uninstall or overwrite dev.cnxdev.pixelcraft"
  echo "NOTE: thermal state/heat/throttling observations must still be recorded manually in docs/G6_RELIABILITY_MATRIX.md"
} | tee "$log"

if DEVICE="$DEVICE" \
  G6_MODE=thermal \
  G6_DURATION_MIN="$DURATION_MIN" \
  G6_SESSION_LOG="$log.session" \
  bash tool/g6_run_device_session.sh; then
  cat "$log.session" >> "$log"
  rm -f "$log.session"
else
  status=$?
  cat "$log.session" >> "$log" 2>/dev/null || true
  rm -f "$log.session"
  echo "[G6.4] FAIL status=$status evidence=$log" | tee -a "$log"
  exit "$status"
fi

{
  echo "[G6.4] PASS"
  echo "[G6.4] evidence=$log"
  echo "[G6.4] NOTE: the installed PixelCraft main app was not targeted by this runner"
} | tee -a "$log"
