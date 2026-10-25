#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$KIT_DIR/patches/hipfire-claude-deepseek-master-56367a7.patch"
SOURCE_DIR="${1:-${HOME}/.hipfire/src}"

if ! git -C "$SOURCE_DIR" apply --reverse --check "$PATCH_FILE"; then
  echo "The patch is not cleanly applied in $SOURCE_DIR; refusing to revert." >&2
  exit 1
fi

git -C "$SOURCE_DIR" apply --reverse "$PATCH_FILE"
echo "Patch reverted from $SOURCE_DIR."
