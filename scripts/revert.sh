#!/usr/bin/env bash
set -euo pipefail
KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-${HOME}/.hipfire/src}"
PATCHES=(
  "$KIT_DIR/patches/hipfire-claude-deepseek-master-56367a7.patch"
  "$KIT_DIR/patches/hipfire-claude-deferred-tools.patch"
  "$KIT_DIR/patches/hipfire-server-search-config.patch"
)
if ! git -C "$SOURCE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not a Git worktree: $SOURCE_DIR" >&2
  exit 2
fi

start=-1
for ((i=${#PATCHES[@]}-1; i>=0; i--)); do
  if git -C "$SOURCE_DIR" apply --reverse --check "${PATCHES[i]}" >/dev/null 2>&1; then
    start=$i
    break
  fi
done
if (( start < 0 )); then
  echo "No recognized patch state; refusing to revert $SOURCE_DIR" >&2
  exit 1
fi
reverted=()
for ((i=start; i>=0; i--)); do
  if ! git -C "$SOURCE_DIR" apply --reverse --check "${PATCHES[i]}" ||
     ! git -C "$SOURCE_DIR" apply --reverse "${PATCHES[i]}"; then
    for ((j=${#reverted[@]}-1; j>=0; j--)); do
      git -C "$SOURCE_DIR" apply "${reverted[j]}"
    done
    echo "Revert failed; this invocation's changes were restored." >&2
    exit 1
  fi
  reverted+=("${PATCHES[i]}")
done
echo "Patches reverted from $SOURCE_DIR."
