#!/bin/bash
set -euo pipefail

OUT="/root/relatorio-mail-cpanel_$(date +%F_%H%M).txt"

mask_line() {
  sed -E \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[IP]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[EMAIL]/g' \
    -e 's/\b([A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b/[DOMINIO]/g'
}

{
  echo "=== DATA ==="
  date
  echo

  echo "=== VERSOES ==="
  (cat /etc/redhat-release 2>/dev/null || lsb_release -a 2>/dev/null || true) | mask_line || true
  echo "cpanel: $(/usr/local/cpanel/cpanel -V 2>/dev/null || echo desconhecido)"
  echo "exim: $(exim -bV 2>/dev/null | head -n1 || echo desconhecido)"
  echo

  echo "=== LIMITES GLOBAIS (cpanel.config) ==="
  if [ -f /var/cpanel/cpanel.config ]; then
    egrep -n '^(maxemailsperhour|email_send_limits|smtp_accept_max_per_connection|smtp_accept_max|max_defer_fail|max_recipients_per_message|max_rcpt|acl_|skipmaxemailsperhour)' \
      /var/cpanel/cpanel.config 2>/dev/null | mask_line || true
  else
    echo "Arquivo /var/cpanel/cpanel.config nao encontrado"
  fi
  echo

  echo "=== LIMITES POR USUARIO (MAXEMAILSPERHOUR) ==="
  if [ -d /var/cpanel/users ]; then
    for f in /var/cpanel/users/*; do
      u="$(basename "$f")"
      v="$(grep -E '^MAXEMAILSPERHOUR=' "$f" 2>/dev/null | head -n1 || true)"
      [ -n "$v" ] && echo "$u $v"
    done | sort | mask_line || true
  else
    echo "Diretorio /var/cpanel/users nao encontrado"
  fi
  echo

  echo "=== EXIM: FILA (TOP 30) ==="
  if command -v exim >/dev/null 2>&1; then
    exim -bp 2>/dev/null | head -n 200 | mask_line || true
    echo
    echo "--- contagem total na fila ---"
    exim -bpc 2>/dev/null || true
    echo
    echo "--- FROZEN (amostra) ---"
    exim -bp 2>/dev/null | grep -i frozen | head -n 100 | mask_line || true
  else
    echo "exim nao encontrado"
  fi
  echo

  echo "=== MAILLOG (ultimas 200 linhas relevantes) ==="
  LOG=""
  [ -f /var/log/exim_mainlog ] && LOG="/var/log/exim_mainlog"
  [ -z "$LOG" ] && [ -f /var/log/exim/mainlog ] && LOG="/var/log/exim/mainlog"
  if [ -n "$LOG" ]; then
    tail -n 200 "$LOG" | egrep -i 'defer|frozen|retry|queue|spam|blocked|rate|throttle|limit' | mask_line || true
  else
    echo "Nao achei exim_mainlog/mainlog"
  fi
  echo

  echo "=== EXIM CONFIG (limites relevantes) ==="
  if [ -f /etc/exim.conf ]; then
    egrep -n 'smtp_accept_max|smtp_accept_max_per_connection|remote_max_parallel|queue|retry|timeout|acl_smtp|acl_check|ratelimit|throttle|max_rcpt|max_recipients' \
      /etc/exim.conf 2>/dev/null | head -n 250 | mask_line || true
  else
    echo "/etc/exim.conf nao encontrado"
  fi

} > "$OUT"

echo "OK: relatorio gerado em: $OUT"
echo "Envie o conteudo desse arquivo aqui."


# bash <(curl -sk https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/relatorio-mail-cpanel.sh)