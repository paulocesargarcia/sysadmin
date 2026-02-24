#!/usr/bin/env bash
# dns-test.sh — Testa resolvedores DNS e exibe tempo médio. Uso: dns-test.sh [DOMÍNIO]
set -euo pipefail

readonly DEFAULT_DOMAIN="cpanel.net"
readonly RESOLVERS=(8.8.8.8 4.2.2.2 1.1.1.1 208.67.220.220 156.154.71.1 216.146.35.35)
readonly RESOLVER_NAMES=("Google" "Level3" "Cloudflare" "OpenDNS" "Neustar" "Dyn")

domain="${1:-$DEFAULT_DOMAIN}"

if ! command -v dig &>/dev/null; then
    echo "Erro: 'dig' não encontrado. Instale bind-utils ou dnsutils." >&2
    exit 1
fi

echo "Domínio: $domain — 3 consultas por resolvedor, 3s entre cada."
echo

for idx in "${!RESOLVERS[@]}"; do
    resolver="${RESOLVERS[$idx]}"
    name="${RESOLVER_NAMES[$idx]}"
    echo "=== $name ($resolver) ==="
    sum=0
    count=0
    for i in 1 2 3; do
        t=$(dig +time=5 +tries=1 "$domain" @"$resolver" 2>/dev/null | awk '/Query time:/ { gsub(/ msec/, ""); print $4; exit }')
        if [[ -n "${t:-}" && "$t" =~ ^[0-9]+$ ]]; then
            echo "  Tentativa $i: ${t} ms"
            sum=$(( sum + t ))
            count=$(( count + 1 ))
        else
            echo "  Tentativa $i: falha" >&2
        fi
        if [[ $i -lt 3 ]]; then sleep 3; fi
    done
    if [[ $count -gt 0 ]]; then
        echo "  Tempo médio: $(( sum / count )) ms"
    else
        echo "  Tempo médio: N/A"
    fi
    echo
done

# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/dns-test.sh")