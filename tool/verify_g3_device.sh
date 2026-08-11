#!/usr/bin/env bash
set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"
DEVICE="${DEVICE:-}"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
DEV_BUNDLE_ID="dev.cnxdev.pixelcraft"
VERIFY_BUNDLE_ID="dev.cnxdev.pixelcraft.g3verify"
DRIVER="test_driver/integration_test.dart"
TARGET="integration_test/g3_editor_gpu_verification_test.dart"

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: set DEVICE to a physical iOS device id." >&2
  echo "Example: DEVICE=00008110-... bash tool/verify_g3_device.sh" >&2
  echo >&2
  "$FLUTTER" devices || true
  exit 2
fi

if [[ ! -f "$PBXPROJ" ]]; then
  echo "ERROR: missing $PBXPROJ" >&2
  exit 2
fi

if [[ ! -f "$DRIVER" || ! -f "$TARGET" ]]; then
  echo "ERROR: missing G3 integration driver/target." >&2
  exit 2
fi

backup="$(mktemp -t pixelcraft-g3-pbxproj.XXXXXX)"
cp "$PBXPROJ" "$backup"
restore_project() {
  cp "$backup" "$PBXPROJ"
  rm -f "$backup"
}
trap restore_project EXIT INT TERM

python3 - "$PBXPROJ" "$DEV_BUNDLE_ID" "$VERIFY_BUNDLE_ID" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source_id = sys.argv[2]
verify_id = sys.argv[3]
text = path.read_text()
needle = f"PRODUCT_BUNDLE_IDENTIFIER = {source_id};"
replacement = f"PRODUCT_BUNDLE_IDENTIFIER = {verify_id};"
count = text.count(needle)
if count != 3:
    raise SystemExit(
        f"ERROR: expected 3 Runner bundle-id settings for {source_id}, found {count}"
    )
path.write_text(text.replace(needle, replacement))
print(f"[PixelCraft G3] temporary verification bundle: {verify_id} ({count} configs)")
PY

echo "[PixelCraft G3] device: $DEVICE"
echo "[PixelCraft G3] app dev bundle remains untouched: $DEV_BUNDLE_ID"
echo "[PixelCraft G3] verification bundle: $VERIFY_BUNDLE_ID"
echo "[PixelCraft G3] running one consolidated flutter drive session"

"$FLUTTER" drive \
  --driver="$DRIVER" \
  --target="$TARGET" \
  -d "$DEVICE"

echo
echo "[PixelCraft G3] AUTOMATED DEVICE GATES: PASS"
echo "[PixelCraft G3] restored iOS project bundle configuration."
echo "Complete the manual lifecycle/cross-tool checklist in docs/G3_DEVICE_VERIFICATION.md before closing G3."
