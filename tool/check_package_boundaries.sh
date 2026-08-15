#!/usr/bin/env bash
set -euo pipefail

status=0

check_pattern() {
  local pattern="$1"
  local description="$2"
  if grep -RInE --include='*.dart' "$pattern" \
    packages/dxtr_pixs_editing \
    packages/dxtr_pixs_film \
    packages/dxtr_pixs_gpu; then
    echo "ERROR: $description"
    status=1
  fi
}

# Internal packages may depend on other packages, but never back on PixelCraft
# application source.
check_pattern "package:pixelcraft/" "package source imports from the PixelCraft app are forbidden"
check_pattern "(^|['\"])(\.\./)+lib/" "relative imports escaping packages back into root lib/ are forbidden"

# The pure editing package is deliberately at the bottom of the Dart package
# graph. It must not learn about Film/GPU/native/application layers.
if grep -RInE --include='*.dart' \
  "package:dxtr_pixs_film/|package:dxtr_pixs_gpu/|package:dxtr_pixs_engine/|package:flutter/|package:flutter_riverpod/" \
  packages/dxtr_pixs_editing; then
  echo "ERROR: dxtr_pixs_editing must remain pure Dart and independent of Film/GPU/engine/Flutter/Riverpod"
  status=1
fi

# Film is a pure Dart product/domain layer above editing. It may depend on
# dxtr_pixs_editing, but not on renderers, the Rust bridge, Flutter, or app UI.
if grep -RInE --include='*.dart' \
  "package:dxtr_pixs_gpu/|package:dxtr_pixs_engine/|package:flutter/|package:flutter_riverpod/|package:path_provider/|dart:io" \
  packages/dxtr_pixs_film; then
  echo "ERROR: dxtr_pixs_film may depend on editing only; platform/rendering dependencies are forbidden"
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Package boundary checks passed."
