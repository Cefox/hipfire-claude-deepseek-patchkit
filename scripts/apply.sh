#!/usr/bin/env bash
set -euo pipefail
KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-${HOME}/.hipfire/src}"
PATCHES=(
  "$KIT_DIR/patches/hipfire-claude-deepseek-master-56367a7.patch"
  "$KIT_DIR/patches/hipfire-claude-deferred-tools.patch"
  "$KIT_DIR/patches/hipfire-server-search-config.patch"
  "$KIT_DIR/patches/hipfire-search-settings-tui.patch"
)
if ! git -C "$SOURCE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not a Git worktree: $SOURCE_DIR" >&2
  exit 2
fi

start=0
for ((i=${#PATCHES[@]}-1; i>=0; i--)); do
  if git -C "$SOURCE_DIR" apply --reverse --check "${PATCHES[i]}" >/dev/null 2>&1; then
    start=$((i+1))
    break
  fi
done
if (( start == ${#PATCHES[@]} )); then
  echo "All compatibility patches are already applied in $SOURCE_DIR"
  exit 0
fi
if (( start == 0 )) && [ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]; then
  echo "Refusing to patch an unrecognized dirty worktree: $SOURCE_DIR" >&2
  exit 2
fi
applied=()
for ((i=start; i<${#PATCHES[@]}; i++)); do
  if ! git -C "$SOURCE_DIR" apply --check "${PATCHES[i]}" ||
     ! git -C "$SOURCE_DIR" apply "${PATCHES[i]}"; then
    for ((j=${#applied[@]}-1; j>=0; j--)); do
      git -C "$SOURCE_DIR" apply --reverse "${applied[j]}"
    done
    echo "Patch failed; this invocation's changes were rolled back. Review/rebase rather than force-applying." >&2
    exit 1
  fi
  applied+=("${PATCHES[i]}")
done
echo "Patches applied. Build/install hipfire-cli, hipfire-daemon and hipfire-tui, then restart/reopen HipFire."
