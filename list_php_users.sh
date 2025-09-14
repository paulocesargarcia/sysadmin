#!/bin/bash
set -euo pipefail

OUT_TXT="/root/php_versions.txt"
OUT_JSON="/root/vhosts.json"
LOG="/root/php_versions.log"
TMP="/root/php_versions.$$.$RANDOM.tmp"

# Log everything
exec > >(tee -a "$LOG") 2>&1

echo "[INFO] Iniciando em $(date -Iseconds)"
echo "[INFO] OUT_TXT=$OUT_TXT | OUT_JSON=$OUT_JSON | LOG=$LOG | TMP=$TMP"

trap 'rm -f "$TMP" || true' EXIT

require() { command -v "$1" >/dev/null 2>&1 || { echo "[ERRO] Comando '$1' não encontrado."; exit 1; }; }
require jq
require whmapi1
require uapi

echo "[INFO] Coletando contas..."
whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  echo "[INFO] Processando usuário: $user"
  uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null |
  jq -c '.result.data[] | {
    vhost: .vhost,
    version: .version,
    documentroot: .documentroot,
    account: .account,
    account_owner: .account_owner,
    main_domain: (.main_domain|tonumber? // 0),
    php_fpm: .php_fpm,
    php_fpm_pool_parms: .php_fpm_pool_parms,
    phpversion_source: .phpversion_source,
    homedir: .homedir
  }'
done > "$TMP"

echo "[INFO] Gravando JSON consolidado em $OUT_JSON"
jq -s . "$TMP" > "$OUT_JSON"

echo "[INFO] Gerando lista de comandos em $OUT_TXT"
jq -r '
  sort_by(.vhost) |
  group_by(.vhost)[] |
  ( (map(select(.main_domain==1))[0]) // .[0] ) |
  "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"
' "$OUT_JSON" | sort -u > "$OUT_TXT"

echo "[OK] Gerado: $OUT_JSON"
echo "[OK] Gerado: $OUT_TXT"
echo "[INFO] Finalizado em $(date -Iseconds)"


# bash -x <(curl -fsSL "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh") 