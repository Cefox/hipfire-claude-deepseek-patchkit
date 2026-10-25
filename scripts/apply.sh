#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$KIT_DIR/patches/hipfire-claude-deepseek-master-56367a7.patch"
DEFERRED_PATCH="$KIT_DIR/patches/hipfire-claude-deferred-tools.patch"
SOURCE_DIR="${1:-${HOME}/.hipfire/src}"

if ! git -C "$SOURCE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not a Git worktree: $SOURCE_DIR" >&2
  exit 2
fi

if git -C "$SOURCE_DIR" apply --reverse --check "$DEFERRED_PATCH" >/dev/null 2>&1; then
  echo "Compatibility and deferred-tool patches are already applied in $SOURCE_DIR"
  exit 0
fi

base_applied=false
if git -C "$SOURCE_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
  base_applied=true
elif [ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]; then
  echo "Refusing to patch a worktree with local changes: $SOURCE_DIR" >&2
  echo "Commit or back up those changes, then retry." >&2
  exit 2
fi

if ! $base_applied && ! git -C "$SOURCE_DIR" apply --check "$PATCH_FILE"; then
  echo "Patch does not apply cleanly to this HipFire revision." >&2
  echo "Use the pinned base revision or rebase/review the patch first." >&2
  exit 1
fi

if ! $base_applied; then
  git -C "$SOURCE_DIR" apply "$PATCH_FILE"
fi
if ! git -C "$SOURCE_DIR" apply --check "$DEFERRED_PATCH"; then
  if ! $base_applied; then
    git -C "$SOURCE_DIR" apply --reverse "$PATCH_FILE"
  fi
  echo "Deferred-tool patch does not apply cleanly; source changes from this run were rolled back." >&2
  exit 1
fi
git -C "$SOURCE_DIR" apply "$DEFERRED_PATCH"
echo "Patches applied. Build the updated hipfire-cli and hipfire-daemon before restarting the service."
