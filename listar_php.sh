#!/bin/bash
# Lista todos os usuários cPanel/WHM, seus domínios e versão do PHP
# Saída: user    domain    php_pkg    php_version

OUT="${1:-/root/php_por_dominio.tsv}"
echo -e "user\tdomain\tphp_pkg\tphp_version" > "$OUT"

# lista todos os usuários do WHM
whmapi1 listaccts --output=json 2>/dev/null \
| jq -r '.data.acct[].user' \
| while read -r user; do
    uapi --user=paraguaymundial LangPHP php_get_vhost_versions --output=json \
    | jq -r '
        .result.data[] |
        [
        .phpversion_source.domain // .vhost,
        .version,
        (.version | capture("ea-php(?<maj>[0-9]+)(?<min>[0-9]+)") | "\(.maj).\(.min)")
        ] | @tsv
    ' >> "$OUT"
done

echo "Gerado: $OUT"

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/listar_php.sh")