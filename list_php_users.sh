#!/bin/bash
set -euo pipefail

whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null |
  jq -cer '.result.data[]? | {
    vhost: .vhost,
    version: .version,
    main_domain: ((.main_domain|tonumber?) // 0)
  }' || true
done |
jq -rs '
  sort_by(.vhost) |
  group_by(.vhost)[] |
  ( (map(select(.main_domain==1))[0]) // .[0] ) |
  "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"
' | sort -u
