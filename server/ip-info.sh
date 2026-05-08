#!/usr/bin/env bash
command -v curl >/dev/null || { echo "curl não encontrado" >&2; exit 1; }
curl -fsSL --connect-timeout 5 --max-time 10 --retry 2 "https://ipinfo.io/${1:-51.79.42.181}"


# Como usar remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/server/ip-info.sh") 51.79.42.181
