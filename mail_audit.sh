#!/usr/bin/env bash
LOG="${1:-/var/log/exim_mainlog}"   # cPanel: /var/log/exim_mainlog

echo "== Top auth_id (SMTP autenticado) =="
grep -ho 'auth_id=[^ ]\+' "$LOG" | cut -d= -f2 | sort | uniq -c | sort -nr | head

echo -e "\n== Envios via processo interno do cPanel =="
grep -h "__cpanel__service__auth__" "$LOG" | wc -l | xargs -I{} echo "{} linhas no log"
grep -h "__cpanel__service__auth__" "$LOG" | tail -n 10

echo -e "\n== Top diretórios de origem (cwd) =="
grep -ho 'cwd=[^ ]\+' "$LOG" | cut -d= -f2 \
| sed 's#/public_html/.*#/public_html#' | sort | uniq -c | sort -nr | head

echo -e "\n== Top scripts PHP (X-PHP-Script) =="
grep -h 'X-PHP-Script' "$LOG" \
| sed -E 's#.*X-PHP-Script: ([^ ]+).*#\1#' | sort | uniq -c | sort -nr | head

echo -e "\n== Top remetentes envelope-from =="
grep -ho '<= [^ ]\+' "$LOG" | awk '{print $2}' | sort | uniq -c | sort -nr | head

echo -e "\n== Mensagens com fila/deferral =="
grep -h "retry time not reached|temporarily rejected|defer" "$LOG" | wc -l

echo -e "\nDicas: veja também /var/log/exim_rejectlog e /var/log/exim_paniclog"


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/mail_audit.sh")