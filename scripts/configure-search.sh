#!/usr/bin/env bash
# Configure the server-owned Search credential using HipFire's key-file model.
set -Eeuo pipefail
HIPFIRE_BIN="${HIPFIRE_BIN:-${HOME}/.hipfire/bin/hipfire}"
KEY_FILE="${1:-${HOME}/.hipfire/secrets/deepseek-api-key}"
SEARCH_URL="${2:-https://api.deepseek.com/v1/tools/search}"
[[ "$KEY_FILE" == /* ]] || { echo 'Key file path must be absolute.' >&2; exit 2; }
"$HIPFIRE_BIN" config explain serve.deepseek_api_key_file >/dev/null
read -r -s -p 'DeepSeek Search API key: ' search_key
printf '\n'
if [[ ${#search_key} -lt 32 || "$search_key" == *[!\!-\~]* ]]; then
  echo 'The key must contain at least 32 printable ASCII characters, without spaces.' >&2
  exit 2
fi
umask 077
mkdir -p -- "$(dirname -- "$KEY_FILE")"
temporary_key="$(mktemp "$(dirname -- "$KEY_FILE")/.deepseek-key.XXXXXX")"
trap 'rm -f -- "$temporary_key"; unset search_key' EXIT
printf '%s\n' "$search_key" > "$temporary_key"
chmod 600 "$temporary_key"
mv -f -- "$temporary_key" "$KEY_FILE"
unset search_key
"$HIPFIRE_BIN" config set serve.deepseek_api_key_file "$KEY_FILE"
"$HIPFIRE_BIN" config set serve.deepseek_search_url "$SEARCH_URL"
echo 'Search configured. Restart HipFire to load the server-owned key.'
