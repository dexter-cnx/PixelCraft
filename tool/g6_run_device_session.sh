#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="${FLUTTER:-flutter}"
DEVICE="${DEVICE:-}"
MODE="${G6_MODE:-reliability}"
CYCLES="${G6_CYCLES:-10}"
DURATION_MIN="${G6_DURATION_MIN:-15}"
LOG="${G6_SESSION_LOG:-}"

PBXPROJ="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
ANDROID_GRADLE="$ROOT/android/app/build.gradle.kts"
DRIVER="$ROOT/test_driver/integration_test.dart"
TARGET="$ROOT/integration_test/g6_device_verification_test.dart"

IOS_MAIN_BUNDLE_ID="dev.cnxdev.pixelcraft"
IOS_VERIFY_BUNDLE_ID="dev.cnxdev.pixelcraft.g6verify"
ANDROID_MAIN_APP_ID="dev.cnxdev.pixelcraft"
ANDROID_VERIFY_APP_ID="dev.cnxdev.pixelcraft.g6verify"

if [[ -z "$DEVICE" ]]; then
  echo "ERROR: set DEVICE=<flutter-device-id>" >&2
  "$FLUTTER" devices || true
  exit 2
fi

case "$MODE" in
  reliability)
    if ! [[ "$CYCLES" =~ ^[0-9]+$ ]] || [[ "$CYCLES" -lt 1 ]]; then
      echo "ERROR: G6_CYCLES must be a positive integer" >&2
      exit 2
    fi
    ;;
  thermal)
    if ! [[ "$DURATION_MIN" =~ ^[0-9]+$ ]] || [[ "$DURATION_MIN" -lt 1 ]]; then
      echo "ERROR: G6_DURATION_MIN must be a positive integer" >&2
      exit 2
    fi
    ;;
  *)
    echo "ERROR: G6_MODE must be reliability or thermal" >&2
    exit 2
    ;;
esac

for required in "$PBXPROJ" "$ANDROID_GRADLE" "$DRIVER" "$TARGET"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: missing $required" >&2
    exit 2
  fi
done

backup_dir="$(mktemp -d -t pixelcraft-g6-session.XXXXXX)"
cp "$PBXPROJ" "$backup_dir/project.pbxproj"
cp "$ANDROID_GRADLE" "$backup_dir/build.gradle.kts"
restored=0

restore_project() {
  if [[ "$restored" -eq 1 ]]; then
    return
  fi
  if [[ -d "$backup_dir" ]]; then
    cp "$backup_dir/project.pbxproj" "$PBXPROJ"
    cp "$backup_dir/build.gradle.kts" "$ANDROID_GRADLE"
    rm -rf "$backup_dir"
  fi
  restored=1
}
trap restore_project EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 - "$PBXPROJ" "$ANDROID_GRADLE" \
  "$IOS_MAIN_BUNDLE_ID" "$IOS_VERIFY_BUNDLE_ID" \
  "$ANDROID_MAIN_APP_ID" "$ANDROID_VERIFY_APP_ID" <<'PY'
from pathlib import Path
import sys

pbx = Path(sys.argv[1])
gradle = Path(sys.argv[2])
ios_main = sys.argv[3]
ios_verify = sys.argv[4]
android_main = sys.argv[5]
android_verify = sys.argv[6]

pbx_text = pbx.read_text()
ios_needle = f"PRODUCT_BUNDLE_IDENTIFIER = {ios_main};"
ios_replacement = f"PRODUCT_BUNDLE_IDENTIFIER = {ios_verify};"
ios_count = pbx_text.count(ios_needle)
if ios_count < 1:
    raise SystemExit(
        f"ERROR: could not find iOS Runner bundle id {ios_main} in {pbx}"
    )
pbx.write_text(pbx_text.replace(ios_needle, ios_replacement))

gradle_text = gradle.read_text()
android_needle = f'applicationId = "{android_main}"'
android_replacement = f'applicationId = "{android_verify}"'
android_count = gradle_text.count(android_needle)
if android_count != 1:
    raise SystemExit(
        f"ERROR: expected one Android applicationId {android_main}, found {android_count}"
    )
gradle.write_text(gradle_text.replace(android_needle, android_replacement))

print(f"[PixelCraft G6] temporary iOS verifier bundle: {ios_verify} ({ios_count} configs)")
print(f"[PixelCraft G6] temporary Android verifier app id: {android_verify}")
PY

cd "$ROOT"
echo "[PixelCraft G6] device: $DEVICE"
echo "[PixelCraft G6] mode: $MODE"
echo "[PixelCraft G6] main app id remains untouched: $IOS_MAIN_BUNDLE_ID"
echo "[PixelCraft G6] verifier app id: $IOS_VERIFY_BUNDLE_ID"
echo "[PixelCraft G6] one consolidated flutter drive session"

cmd=(
  "$FLUTTER" drive
  "--driver=$DRIVER"
  "--target=$TARGET"
  -d "$DEVICE"
  "--dart-define=G6_MODE=$MODE"
  "--dart-define=G6_CYCLES=$CYCLES"
  "--dart-define=G6_DURATION_MIN=$DURATION_MIN"
)

if [[ -n "$LOG" ]]; then
  mkdir -p "$(dirname "$LOG")"
  set +e
  "${cmd[@]}" 2>&1 | tee "$LOG"
  status=${PIPESTATUS[0]}
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "[PixelCraft G6] DEVICE SESSION FAIL status=$status log=$LOG" >&2
    exit "$status"
  fi
else
  "${cmd[@]}"
fi

restore_project
trap - EXIT

echo "[PixelCraft G6] DEVICE SESSION PASS"
echo "[PixelCraft G6] restored project bundle/application-id configuration"
