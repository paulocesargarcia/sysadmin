#!/bin/bash
set -euo pipefail

OUT_TXT="/root/php_versions.txt"
TMP="/root/php_versions.$$.$RANDOM.tmp"
trap 'rm -f "$TMP" || true' EXIT

# Coleta usuários e extrai apenas JSON válido dos vhosts
whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null |
  jq -cer '.result.data[]? | {
    vhost: .vhost,
    version: .version,
    main_domain: ((.main_domain|tonumber?) // 0)
  }' || true
done > "$TMP"

# Gera lista única por vhost (prioriza main_domain==1)
if [ -s "$TMP" ]; then
  jq -rs '
    sort_by(.vhost) |
    group_by(.vhost)[] |
    ( (map(select(.main_domain==1))[0]) // .[0] ) |
    "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"
  ' "$TMP" | sort -u > "$OUT_TXT"
else
  : > "$OUT_TXT"
fi

echo "$OUT_TXT"
