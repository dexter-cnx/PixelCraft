#!/usr/bin/env bash
set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"
DEVICE="${DEVICE:-}"

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: set DEVICE to a physical iOS device id." >&2
  echo "Example: DEVICE=00008110-... bash tool/verify_g3_device.sh" >&2
  echo >&2
  "$FLUTTER" devices || true
  exit 2
fi

echo "[PixelCraft G3] device: $DEVICE"
echo "[PixelCraft G3] 1/2 canonical native Film/LUT parity"
"$FLUTTER" test integration_test/gpu_preview_harness_test.dart -d "$DEVICE"

echo
echo "[PixelCraft G3] 2/2 Editor GPU parity, latency and renderer recreation"
"$FLUTTER" test integration_test/g3_editor_gpu_verification_test.dart -d "$DEVICE"

echo
echo "[PixelCraft G3] AUTOMATED DEVICE GATES: PASS"
echo "Complete the manual lifecycle/cross-tool checklist in docs/G3_DEVICE_VERIFICATION.md before closing G3."
