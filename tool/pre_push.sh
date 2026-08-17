#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail_missing() {
  local tool="$1"
  echo "[Pixel Craft] pre-push: required tool '$tool' is unavailable" >&2
  echo "Install the repository toolchain, then retry the push." >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail_missing git
command -v make >/dev/null 2>&1 || fail_missing make
command -v dart >/dev/null 2>&1 || fail_missing dart
command -v cargo >/dev/null 2>&1 || fail_missing cargo

if ! cargo fmt --version >/dev/null 2>&1; then
  echo "[Pixel Craft] pre-push: rustfmt is unavailable" >&2
  echo "Install it with: rustup component add rustfmt" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "[Pixel Craft] pre-push: working tree must be clean before formatting" >&2
  git status --short >&2
  echo "Commit, stash, or otherwise resolve local changes before pushing." >&2
  exit 1
fi

echo "[Pixel Craft] pre-push: running canonical Dart and Rust formatting"
if ! make format; then
  echo "[Pixel Craft] pre-push: formatter failed; push aborted" >&2
  if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "Files changed before the formatter failed:" >&2
    git status --short >&2
  fi
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "[Pixel Craft] pre-push: formatting changed files; push aborted" >&2
  echo "Review and commit these formatting changes first:" >&2
  git status --short >&2
  echo "Then run git push again." >&2
  exit 1
fi

echo "[Pixel Craft] pre-push: formatting guard PASS"
