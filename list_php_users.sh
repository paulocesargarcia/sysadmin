#!/bin/bash
set -u -o pipefail

TMP="/root/php_versions.$$.$RANDOM.tmp"
trap 'rm -f "$TMP" || true' EXIT

command -v jq >/dev/null || { echo "jq não encontrado" >&2; exit 1; }
command -v whmapi1 >/dev/null || { echo "whmapi1 não encontrado" >&2; exit 1; }
command -v uapi >/dev/null || { echo "uapi não encontrado" >&2; exit 1; }

whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  json="$(uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null || true)"
  [ -z "$json" ] && continue
  jq -cer '.result.data[]? | {
    vhost: .vhost,
    version: .version,
    main_domain: ((.main_domain|tonumber?) // 0)
  }' <<<"$json" || true
done > "$TMP"

if [ -s "$TMP" ]; then
  jq -rs '
    sort_by(.vhost) |
    group_by(.vhost)[] |
    ( (map(select(.main_domain==1))[0]) // .[0] ) |
    "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"
  ' "$TMP" | sort -u
fi
