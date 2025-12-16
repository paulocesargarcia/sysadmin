#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 email@destino.com"
  exit 1
fi

DESTINO="$1"
HOST="$(hostname)"
DATA="$(date +%F_%H%M)"
OUT="/root/relatorio-mail-cpanel_${HOST}_${DATA}.txt"
ASSUNTO="Relatorio Mail cPanel/Exim - ${HOST} - ${DATA}"

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
  [ -f /var/cpanel/cpanel.config ] \
    && egrep -n '^(maxemailsperhour|email_send_limits|smtp_accept_max|max_defer_fail|max_rcpt|skipmaxemailsperhour)' /var/cpanel/cpanel.config | mask_line \
    || echo "Arquivo nao encontrado"
  echo

  echo "=== LIMITES POR USUARIO ==="
  for f in /var/cpanel/users/*; do
    u="$(basename "$f")"
    v="$(grep -E '^MAXEMAILSPERHOUR=' "$f" 2>/dev/null || true)"
    [ -n "$v" ] && echo "$u $v"
  done | sort | mask_line
  echo

  echo "=== EXIM FILA / FROZEN ==="
  exim -bpc
  echo
  exim -bp | grep -i frozen | head -n 100 | mask_line || true
  echo

  echo "=== MAILLOG (resumo) ==="
  LOG="/var/log/exim_mainlog"
  [ -f /var/log/exim/mainlog ] && LOG="/var/log/exim/mainlog"
  tail -n 200 "$LOG" | egrep -i 'defer|frozen|retry|rate|limit|throttle' | mask_line || true

} > "$OUT"

echo "Relatorio gerado em $OUT"

if command -v mail >/dev/null 2>&1; then
  mail -s "$ASSUNTO" "$DESTINO" < "$OUT"
elif command -v sendmail >/dev/null 2>&1; then
  {
    echo "Subject: $ASSUNTO"
    echo "To: $DESTINO"
    echo
    cat "$OUT"
  } | sendmail -t
else
  echo "ERRO: mail/sendmail nao encontrado"
  exit 2
fi

echo "Email enviado para $DESTINO"



# bash <(curl -sk https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/relatorio-mail-cpanel.sh)