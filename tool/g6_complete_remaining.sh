#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${G6_OUT_DIR:-$ROOT/build/g6/final}"
MAX_MP="${G6_MAX_MP:-48}"
DEVICE="${DEVICE:-}"

if ! [[ "$MAX_MP" =~ ^(12|24|48)$ ]]; then
  echo "ERROR: G6_MAX_MP must be 12, 24, or 48" >&2
  exit 2
fi

mkdir -p "$OUT"
cd "$ROOT"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
summary="$OUT/${stamp}-summary.txt"

run_step() {
  local name="$1"
  shift
  local log="$OUT/${stamp}-${name}.log"
  echo "[G6 FINAL] START $name" | tee -a "$summary"
  set +e
  "$@" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "[G6 FINAL] FAIL $name status=$status log=$log" | tee -a "$summary"
    exit "$status"
  fi
  echo "[G6 FINAL] PASS $name" | tee -a "$summary"
}

{
  echo "PixelCraft G6 remaining validation"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "branch=$(git branch --show-current 2>/dev/null || echo unknown)"
  echo "max_mp=$MAX_MP"
  echo "device=${DEVICE:-not-set}"
  echo "main_app_policy=do not uninstall or overwrite dev.cnxdev.pixelcraft"
} | tee "$summary"

# G6.0 final host baseline.
run_step host_baseline bash tool/g6_host_baseline.sh

# G6.1 deterministic image-size characterization. Run each tier explicitly so
# evidence files identify the highest tier that actually completed.
run_step image_12mp env G6_MAX_MP=12 cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture
if [[ "$MAX_MP" -ge 24 ]]; then
  run_step image_24mp env G6_MAX_MP=24 cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture
fi
if [[ "$MAX_MP" -ge 48 ]]; then
  run_step image_48mp env G6_MAX_MP=48 cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture
fi

# G6.5 deterministic recovery/profile corruption coverage.
run_step failure_injection flutter test test/state/g6_failure_injection_test.dart

# Optional device automation. This is intentionally only the automated portion;
# camera permissions, lifecycle interruption, gallery denial, and native GPU
# failure observation remain manual evidence in docs/G6_DEVICE_MANUAL_CHECKLIST.md.
if [[ -n "$DEVICE" ]]; then
  run_step device_smoke env DEVICE="$DEVICE" G6_CYCLES=10 bash tool/g6_device_reliability.sh
else
  echo "[G6 FINAL] SKIP device_smoke (set DEVICE=<flutter-device-id> to include it)" | tee -a "$summary"
fi

{
  echo "[G6 FINAL] AUTOMATED REMAINING VALIDATION PASS"
  echo "[G6 FINAL] evidence=$OUT"
  echo "[G6 FINAL] next=complete docs/G6_DEVICE_MANUAL_CHECKLIST.md on each available physical device"
} | tee -a "$summary"
