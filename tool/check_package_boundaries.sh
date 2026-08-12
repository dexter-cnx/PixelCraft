#!/usr/bin/env bash
set -euo pipefail

status=0

check_pattern() {
  local pattern="$1"
  local description="$2"
  if grep -RInE --include='*.dart' "$pattern" packages/pixelcraft_editing packages/pixelcraft_gpu; then
    echo "ERROR: $description"
    status=1
  fi
}

# Internal packages may depend on other packages, but never back on PixelCraft
# application source.
check_pattern "package:pixelcraft/" "package source imports from the PixelCraft app are forbidden"
check_pattern "(^|['\"])(\.\./)+lib/" "relative imports escaping packages back into root lib/ are forbidden"

# The pure editing package is deliberately at the bottom of the Dart package
# graph. It must not learn about GPU/native/application layers.
if grep -RInE --include='*.dart' "package:pixelcraft_gpu/|package:flutter/|package:flutter_riverpod/" packages/pixelcraft_editing; then
  echo "ERROR: pixelcraft_editing must remain pure Dart and independent of GPU/Flutter/Riverpod"
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Package boundary checks passed."
