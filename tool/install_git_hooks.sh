#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "[Pixel Craft] hooks-install: run this inside the PixelCraft repository" >&2
  exit 1
fi

cd "$ROOT"
git config --local core.hooksPath .githooks
chmod +x .githooks/pre-push tool/pre_push.sh tool/install_git_hooks.sh

configured="$(git config --local --get core.hooksPath || true)"
if [[ "$configured" != ".githooks" ]]; then
  echo "[Pixel Craft] hooks-install: failed to activate .githooks" >&2
  exit 1
fi

echo "[Pixel Craft] repository Git hooks are active (.githooks); git push now runs the pre-push formatting guard."
