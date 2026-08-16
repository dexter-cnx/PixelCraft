#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAIN_ID="dev.cnxdev.pixelcraft"
VERIFY_ID="dev.cnxdev.pixelcraft.g6verify"
RUNNER="tool/g6_run_device_session.sh"
FINAL="tool/g6_complete_remaining.sh"
ANDROID="android/app/build.gradle.kts"
IOS="ios/Runner.xcodeproj/project.pbxproj"

fail() {
  echo "[PixelCraft CI] DEVICE SAFETY FAIL: $*" >&2
  exit 1
}

[[ -f "$RUNNER" ]] || fail "missing $RUNNER"
[[ -f "$FINAL" ]] || fail "missing $FINAL"
[[ -f "$ANDROID" ]] || fail "missing $ANDROID"
[[ -f "$IOS" ]] || fail "missing $IOS"
[[ "$MAIN_ID" != "$VERIFY_ID" ]] || fail "verifier id must differ from main app id"

grep -Fq "applicationId = \"$MAIN_ID\"" "$ANDROID" || fail "Android main applicationId changed unexpectedly"
grep -Fq "PRODUCT_BUNDLE_IDENTIFIER = $MAIN_ID;" "$IOS" || fail "iOS main bundle id changed unexpectedly"
grep -Fq "IOS_MAIN_BUNDLE_ID=\"$MAIN_ID\"" "$RUNNER" || fail "G6 iOS main id invariant missing"
grep -Fq "IOS_VERIFY_BUNDLE_ID=\"$VERIFY_ID\"" "$RUNNER" || fail "G6 iOS verifier id invariant missing"
grep -Fq "ANDROID_MAIN_APP_ID=\"$MAIN_ID\"" "$RUNNER" || fail "G6 Android main id invariant missing"
grep -Fq "ANDROID_VERIFY_APP_ID=\"$VERIFY_ID\"" "$RUNNER" || fail "G6 Android verifier id invariant missing"
grep -Fq 'git worktree add --detach "$WORKTREE" HEAD' "$RUNNER" || fail "G6 verifier must use an isolated detached worktree"
grep -Fq 'trap cleanup EXIT' "$RUNNER" || fail "G6 verifier worktree cleanup trap missing"
grep -Fq "main_app_policy=do not uninstall or overwrite $MAIN_ID" "$FINAL" || fail "G6 main-app preservation policy missing"

if grep -R -n -E "(flutter[[:space:]]+uninstall|adb[[:space:]]+uninstall)[^#]*${MAIN_ID}([[:space:]\"']|$)" tool/g6_*.sh "$RUNNER" 2>/dev/null; then
  fail "G6 tooling contains an uninstall command targeting the main app"
fi

python3 - "$RUNNER" "$MAIN_ID" "$VERIFY_ID" <<'PY'
from pathlib import Path
import sys

runner = Path(sys.argv[1]).read_text(encoding="utf-8")
main_id, verify_id = sys.argv[2], sys.argv[3]
required = [
    'PBXPROJ="$WORKTREE/ios/Runner.xcodeproj/project.pbxproj"',
    'ANDROID_GRADLE="$WORKTREE/android/app/build.gradle.kts"',
    'pbx.write_text(pbx_text.replace(ios_needle, ios_replacement))',
    'gradle.write_text(gradle_text.replace(android_needle, android_replacement))',
]
missing = [needle for needle in required if needle not in runner]
if missing:
    raise SystemExit(f"isolated verifier mutation contract missing: {missing}")
if main_id == verify_id:
    raise SystemExit("main and verifier identifiers must differ")
PY

echo "[PixelCraft CI] device safety guard PASS"
echo "[PixelCraft CI] main app: $MAIN_ID"
echo "[PixelCraft CI] isolated verifier: $VERIFY_ID"
