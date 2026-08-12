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
safe_device="${DEVICE//[^A-Za-z0-9_.-]/_}"
summary="$OUT/${stamp}-${safe_device}-summary.txt"
log="$OUT/${stamp}-${safe_device}-session.log"
metrics="$OUT/${stamp}-${safe_device}-metrics.txt"

{
  echo "PixelCraft G6 device reliability"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "branch=$(git branch --show-current 2>/dev/null || echo unknown)"
  echo "device=$DEVICE"
  echo "cycles=$CYCLES"
  echo "session=single flutter drive"
  echo "main_app_policy=do not uninstall or overwrite dev.cnxdev.pixelcraft"
  flutter devices
} | tee "$summary"

echo "[G6] START consolidated reliability session" | tee -a "$summary"

if DEVICE="$DEVICE" \
  G6_MODE=reliability \
  G6_CYCLES="$CYCLES" \
  G6_SESSION_LOG="$log" \
  bash tool/g6_run_device_session.sh; then
  echo "[G6] PASS consolidated reliability session" | tee -a "$summary"
else
  status=$?
  echo "[G6] FAIL consolidated reliability session status=$status log=$log" | tee -a "$summary"
  exit "$status"
fi

# Keep numeric/diagnostic lines in one compact file for later matrix transcription.
grep -hE 'PIXELCRAFT_(PROFILE|MEMORY|G6_)' "$log" > "$metrics" || true

{
  echo "[G6] metrics=$metrics"
  echo "[G6] DEVICE RUN PASS evidence=$OUT"
  echo "[G6] NOTE: the installed PixelCraft main app was not targeted by this runner"
} | tee -a "$summary"
