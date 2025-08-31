#!/bin/bash
# php_map.sh — dump|apply [--dry-run]
set -euo pipefail
FILE="/root/phpmap.json"

need(){ command -v "$1" >/dev/null || { echo "Falta: $1" >&2; exit 1; }; }
need whmapi1; need uapi; need jq

mode="${1:-}"; flag="${2:-}"

dump(){
  tmp="$(mktemp)"
  whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
  while read -r user; do
    uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null |
    jq -c --arg user "$user" '.result.data[] | {user:$user, vhost:.vhost, version_pkg:.version}'
  done > "$tmp"
  jq -s . "$tmp" > "$FILE"; rm -f "$tmp"
  echo "Gerado: $FILE"
}

apply(){
  [[ -f "$FILE" ]] || { echo "Arquivo não encontrado: $FILE" >&2; exit 1; }
  jq -cr '.[] | select(.version_pkg|startswith("ea-php")) | [.vhost,.version_pkg] | @tsv' "$FILE" |
  while IFS=$'\t' read -r vhost pkg; do
    [[ -z "$vhost" || -z "$pkg" ]] && continue
    if [[ "${flag:-}" == "--dry-run" ]]; then
      echo "whmapi1 php_set_vhost_versions version='$pkg' vhost='$vhost'"
    else
      whmapi1 php_set_vhost_versions version="$pkg" vhost="$vhost"
    fi
  done
}

case "$mode" in
  dump)  dump ;;
  apply) apply ;;
  *) echo "Uso: $0 dump|apply [--dry-run]"; exit 1 ;;
esac




# DUMP (gera /root/phpmap.json) + log
# bash -x <(curl -fsSL "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh") dump 2>&1 | tee /root/php_dump.log

# APPLY (usa /root/phpmap.json) + log
# bash -x <(curl -fsSL "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh") apply --dry-run  2>&1 | tee /root/php_apply.log

# bash -x <(curl -fsSL "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh") apply  2>&1 | tee /root/php_apply.log

