#!/bin/bash
set -euo pipefail

OUT_TXT="/root/php_versions.txt"
OUT_JSON="/root/vhosts.json"
TMP="/root/php_versions.$$.$RANDOM.tmp"

trap 'rm -f "$TMP" || true' EXIT

# coleta dados de todos os usuários
whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null |
  jq -c '.result.data[] | {
    vhost: .vhost,
    version: .version,
    main_domain: (.main_domain|tonumber? // 0)
  }'
done > "$TMP"

# grava JSON consolidado
jq -s . "$TMP" > "$OUT_JSON"

# gera lista de comandos única por vhost (prioriza main_domain==1)
jq -r '
  sort_by(.vhost) |
  group_by(.vhost)[] |
  ( (map(select(.main_domain==1))[0]) // .[0] ) |
  "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"
' "$OUT_JSON" | sort -u > "$OUT_TXT"

echo "Gerado: $OUT_JSON e $OUT_TXT"
