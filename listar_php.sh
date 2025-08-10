#!/bin/bash
# Lista todos os usuários cPanel e, por domínio/subdomínio, a versão do PHP
# Saída: user<TAB>domain<TAB>php_pkg<TAB>php_version
# Uso: ./listar_php.sh [/caminho/saida.tsv]

set -euo pipefail
OUT="${1:-/root/php_por_dominio.tsv}"
echo -e "user\tdomain\tphp_pkg\tphp_version" > "$OUT"

# Lista usuários do WHM
whmapi1 listaccts --output=yaml 2>/dev/null | awk '/^  user: /{print $2}' | while read -r user; do
  uapi --user="$user" LangPHP php_get_vhost_versions 2>/dev/null | awk -v usr="$user" '
    /^[[:space:]]+-[[:space:]]*$/ { next }                                   # separador de item
    /^[[:space:]]+vhost:/           { vh=$2; next }
    /^[[:space:]]+phpversion_source:/ { insrc=1; next }
    insrc && /^[[:space:]]+domain:/ { dom=$2; insrc=0; next }
    /^[[:space:]]+version:/ {
        ver=$2
        d = (dom && dom!="") ? dom : vh
        vnum = "-"
        if (match(ver, /ea-php([0-9]+)([0-9]+)/, m)) vnum=m[1] "." m[2]
        printf "%s\t%s\t%s\t%s\n", usr, d, ver, vnum
        dom=""; vh=""
    }
  ' >> "$OUT"
done

echo "Gerado: $OUT"


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/listar_php.sh")