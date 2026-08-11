#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

printf '\n[Pixel Craft] G2 final host verification\n'
printf '[1/7] Flutter analyzer\n'
flutter analyze

printf '\n[2/7] Dart unit + widget tests\n'
make test

printf '\n[3/7] Golden tests\n'
make golden-test

printf '\n[4/7] Rust formatting\n'
make rust-fmt

printf '\n[5/7] Rust clippy\n'
make rust-clippy

printf '\n[6/7] Rust unit tests\n'
make rust-test

printf '\n[7/7] Canonical Film + Creative LUT verification\n'
make gpu-lut-verify

cat <<'EOF'

[Pixel Craft] G2 HOST GATE: PASS

Physical-device closure evidence is recorded separately in:
  docs/G2_FINAL_VERIFICATION.md

Before merging feature/camera-film-preview, perform the final manual smoke flow:
  Camera Film preview
    -> clean capture
    -> Adjust multi-draft
    -> Creative
    -> Film
    -> Sharpen / Gaussian Blur
    -> Crop / Straighten / Rotate / Flip
    -> Undo / Redo
    -> Apply / Cancel
    -> full-resolution export

Rust must remain authoritative after every committed edit and export.
EOF
