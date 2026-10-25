#!/usr/bin/env bash
# Build/install the CLI, daemon AND the separately linked config interface.
set -Eeuo pipefail
SOURCE_DIR="${1:-${HOME}/.hipfire/src}"
INSTALL_ROOT="${2:-${HOME}/.hipfire}"
cd -- "$SOURCE_DIR"
cargo build --release --locked -p hipfire-cli -p hipfire-daemon -p hipfire-tui
TARGET_DIR="${CARGO_TARGET_DIR:-${SOURCE_DIR}/target}"
for name in hipfire daemon hipfire-tui; do
  [[ -x "$TARGET_DIR/release/$name" ]] || { echo "Missing binary: $name" >&2; exit 1; }
done
backup="$INSTALL_ROOT/backups/patchkit-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$backup"
mkdir -p -- "$INSTALL_ROOT/bin"
for name in hipfire daemon hipfire-tui; do
  if [[ -e "$INSTALL_ROOT/bin/$name" ]]; then
    cp -p -- "$INSTALL_ROOT/bin/$name" "$backup/$name"
  fi
  install -m 755 "$TARGET_DIR/release/$name" "$INSTALL_ROOT/bin/$name.patchkit-new"
  mv -f -- "$INSTALL_ROOT/bin/$name.patchkit-new" "$INSTALL_ROOT/bin/$name"
done
echo "Installed hipfire, daemon and hipfire-tui. Backup: $backup"
echo 'Restart HipFire and reopen hipfire config to load the new binaries.'
