#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${G6_OUT_DIR:-$ROOT/build/g6/baseline}"
mkdir -p "$OUT"
cd "$ROOT"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
summary="$OUT/summary-$stamp.txt"

{
  echo "PixelCraft G6.0 host baseline"
  echo "utc=$stamp"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "branch=$(git branch --show-current 2>/dev/null || echo unknown)"
  echo "host=$(uname -a)"
  echo
  flutter --version || true
  rustc --version || true
  cargo --version || true
} | tee "$summary"

run_step() {
  local name="$1"
  shift
  local log="$OUT/${stamp}-${name}.log"
  echo "[G6.0] START $name" | tee -a "$summary"
  if "$@" 2>&1 | tee "$log"; then
    echo "[G6.0] PASS  $name" | tee -a "$summary"
  else
    local status=${PIPESTATUS[0]}
    echo "[G6.0] FAIL  $name status=$status log=$log" | tee -a "$summary"
    exit "$status"
  fi
}

run_step flutter_analyze flutter analyze
run_step flutter_tests make test
run_step golden_tests make golden-test
run_step rust_fmt make rust-fmt
run_step rust_clippy make rust-clippy
run_step rust_tests make rust-test
run_step gpu_lut_verify make gpu-lut-verify

echo "[G6.0] BASELINE PASS evidence=$OUT" | tee -a "$summary"
