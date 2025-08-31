#!/bin/bash
# Uso:
#   ./php_map.sh dump  /root/phpmap.json
#   ./php_map.sh apply /root/phpmap.json [--dry-run]

set -euo pipefail
need(){ command -v "$1" >/dev/null || { echo "Falta: $1" >&2; exit 1; }; }
need whmapi1; need uapi; need jq

MODE="${1:-}"; FILE="${2:-}"; DRY="${3:-}"
[[ -z "$MODE" || -z "$FILE" ]] && { echo "Uso: $0 dump|apply <arquivo.json> [--dry-run]"; exit 1; }

dump() {
  tmp="$(mktemp)"
  # NDJSON: {user,vhost,version_pkg,version}
  whmapi1 listaccts --output=json 2>/dev/null \
  | jq -r '.data.acct[].user' \
  | while read -r user; do
      uapi --user="$user" LangPHP php_get_vhost_versions --output=json 2>/dev/null \
      | jq -c --arg user "$user" '
          .result.data[] |
          { user:$user,
            vhost:.vhost,
            version_pkg:.version,
            version: (if (.version|test("^ea-php[0-9]{2}$"))
                        then (.version | capture("^ea-php(?<maj>[0-9]{1,2})(?<min>[0-9])$") | "\(.maj).\(.min)")
                        else null end)
          }'
    done > "$tmp"
  jq -s '.' "$tmp" > "$FILE"; rm -f "$tmp"
  echo "Gerado: $FILE"
}

apply() {
  jq -cr '.[] | select(.version_pkg|startswith("ea-php")) | [.vhost,.version_pkg] | @tsv' "$FILE" \
  | while IFS=$'\t' read -r vhost pkg; do
      [[ -z "$vhost" || -z "$pkg" ]] && continue
      if [[ "${DRY:-}" == "--dry-run" ]]; then
        echo "whmapi1 php_set_vhost_versions version='$pkg' vhost='$vhost'"
      else
        whmapi1 php_set_vhost_versions version="$pkg" vhost="$vhost"
      fi
    done
}

case "$MODE" in
  dump)  dump ;;
  apply) apply ;;
  *) echo "Modo inválido: $MODE"; exit 1 ;;
esac

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh")