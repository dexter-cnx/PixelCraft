#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mode="check"
if [[ "${1:-}" == "--write" ]]; then
  mode="write"
  shift
elif [[ "${1:-}" == "--check" ]]; then
  shift
fi

if ! command -v dart >/dev/null 2>&1; then
  echo "[Pixel Craft] Dart formatter is unavailable; install/activate the repository Flutter/Dart toolchain." >&2
  exit 1
fi

declare -A seen=()
files=()

add_file() {
  local file="$1"
  [[ "$file" == *.dart ]] || return 0
  [[ -f "$file" ]] || return 0
  [[ -n "${seen[$file]:-}" ]] && return 0
  seen[$file]=1
  files+=("$file")
}

add_from_command() {
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] && add_file "$file"
  done
}

if (( $# > 0 )); then
  for file in "$@"; do
    add_file "$file"
  done
else
  base=""
  if [[ -n "${CI_BASE_SHA:-}" ]] && git cat-file -e "${CI_BASE_SHA}^{commit}" 2>/dev/null; then
    base="$CI_BASE_SHA"
  elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    # pull_request checkout is intentionally shallow. Fetch only its base ref so
    # formatting can be scoped to the PR delta without fetching repository history.
    git fetch --quiet --no-tags --depth=1 origin "$GITHUB_BASE_REF"
    base="FETCH_HEAD"
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    base="$(git merge-base HEAD origin/main)"
  elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    base="HEAD^"
  fi

  if [[ -n "$base" ]]; then
    add_from_command < <(git diff --name-only --diff-filter=ACMR "$base" HEAD -- '*.dart')
  fi

  # Local formatting/preflight also covers worktree, staged and new untracked Dart files.
  add_from_command < <(git diff --name-only --diff-filter=ACMR -- '*.dart')
  add_from_command < <(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
  add_from_command < <(git ls-files --others --exclude-standard -- '*.dart')
fi

if (( ${#files[@]} == 0 )); then
  echo "[Pixel Craft] Dart format-${mode}: no changed Dart files"
  exit 0
fi

printf '[Pixel Craft] Dart format-%s: %d changed Dart file(s)\n' "$mode" "${#files[@]}"
printf '  %s\n' "${files[@]}"

if [[ "$mode" == "write" ]]; then
  dart format "${files[@]}"
else
  dart format --output=none --set-exit-if-changed "${files[@]}"
fi
