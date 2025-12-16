#!/bin/bash
set -u
set -o pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 email@destino.com"
  exit 1
fi

DESTINO="$1"
HOST="$(hostname 2>/dev/null || echo unknown-host)"
DATA="$(date +%F_%H%M 2>/dev/null || echo unknown-date)"
OUT="/root/relatorio-mail-cpanel_${HOST}_${DATA}.txt"
ASSUNTO="Relatorio Mail cPanel/Exim - ${HOST} - ${DATA}"

mask_line() {
  sed -E \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[IP]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[EMAIL]/g' \
    -e 's/\b([A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b/[DOMINIO]/g'
}

run() { "$@" 2>&1 || true; }

# --- gera relatorio ---
{
  echo "=== DATA ==="
  run date
  echo

  echo "=== HOST ==="
  echo "$HOST"
  echo

  echo "=== VERSOES ==="
  (run cat /etc/redhat-release || run lsb_release -a) | mask_line || true
  echo "cpanel: $(run /usr/local/cpanel/cpanel -V | head -n1 | mask_line)"
  echo "exim: $(run exim -bV | head -n1 | mask_line)"
  echo

  echo "=== LIMITES GLOBAIS (cpanel.config) ==="
  if [ -f /var/cpanel/cpanel.config ]; then
    run egrep -n '^(maxemailsperhour|email_send_limits|smtp_accept_max(_per_connection)?|smtp_accept_max|max_defer_fail|max_rcpt|skipmaxemailsperhour)' \
      /var/cpanel/cpanel.config | mask_line || true
  else
    echo "Arquivo /var/cpanel/cpanel.config nao encontrado"
  fi
  echo

  echo "=== LIMITES POR USUARIO (max 10) ==="
  if [ -d /var/cpanel/users ]; then
    run ls -1 /var/cpanel/users 2>/dev/null | sort | head -n 10 | while read -r u; do
      [ -z "$u" ] && continue
      f="/var/cpanel/users/$u"
      v="$(run grep -E '^MAXEMAILSPERHOUR=' "$f" | head -n1)"
      if [ -n "${v:-}" ]; then
        echo "$u $v"
      else
        echo "$u MAXEMAILSPERHOUR=(nao definido)"
      fi
    done | mask_line || true
  else
    echo "Diretorio /var/cpanel/users nao encontrado"
  fi
  echo

  echo "=== EXIM FILA / FROZEN ==="
  if command -v exim >/dev/null 2>&1; then
    echo "--- total na fila ---"
    run exim -bpc
    echo
    echo "--- amostra fila (primeiras 200 linhas) ---"
    run exim -bp | head -n 200 | mask_line || true
    echo
    echo "--- frozen (ate 100) ---"
    run exim -bp | grep -i frozen | head -n 100 | mask_line || true
  else
    echo "exim nao encontrado"
  fi
  echo

  echo "=== MAILLOG (ultimas 200 linhas relevantes) ==="
  LOG=""
  [ -f /var/log/exim_mainlog ] && LOG="/var/log/exim_mainlog"
  [ -z "$LOG" ] && [ -f /var/log/exim/mainlog ] && LOG="/var/log/exim/mainlog"
  if [ -n "$LOG" ]; then
    run tail -n 200 "$LOG" | egrep -i 'defer|frozen|retry|queue|blocked|rate|throttle|limit' | mask_line || true
  else
    echo "Nao achei /var/log/exim_mainlog nem /var/log/exim/mainlog"
  fi
  echo

  echo "=== EXIM CONFIG (trechos de limites relevantes) ==="
  if [ -f /etc/exim.conf ]; then
    run egrep -n 'smtp_accept_max|smtp_accept_max_per_connection|remote_max_parallel|queue|retry|timeout|acl_smtp|acl_check|ratelimit|throttle|max_rcpt|max_recipients' \
      /etc/exim.conf | head -n 250 | mask_line || true
  else
    echo "/etc/exim.conf nao encontrado"
  fi

} > "$OUT"

echo "Relatorio gerado em $OUT"

# --- envia email com ANEXO ---
if command -v mail >/dev/null 2>&1; then
  # precisa ser mailx/s-nail (suporta -a)
  if mail -V 2>/dev/null | egrep -qi '(s-nail|mailx|heirloom)'; then
    echo "Enviando email com anexo via mail..."
    mail -s "$ASSUNTO" -a "$OUT" "$DESTINO" <<< "Relatorio em anexo."
    echo "Email enviado para $DESTINO"
  else
    echo "ERRO: comando 'mail' encontrado, mas nao identifiquei suporte a anexo (-a)."
    echo "Instale s-nail: yum install -y s-nail"
    exit 2
  fi
else
  echo "ERRO: comando 'mail' nao encontrado. Instale s-nail:"
  echo "yum install -y s-nail"
  exit 2
fi

# bash <(curl -sk https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/relatorio-mail-cpanel.sh) paulo@setik.com.py