#!/usr/bin/env bash
# Coleta alertas do iContact no Exim e envia 1 digest diário.
# Uso:
#   ./cpanel_icontact_digest.sh collect        # rodar de hora em hora (cron)
#   ./cpanel_icontact_digest.sh send you@dominio.com  # 1x por dia (cron)

LOG="${EXIM_LOG:-/var/log/exim_mainlog}"
WORKDIR="/var/log/mail_audit"
TODAY="$(date +%F)"
DIGEST="$WORKDIR/digest-$TODAY.txt"

mkdir -p "$WORKDIR" || exit 1

collect_hour() {
  # Janela da última hora
  START="$(date -d '1 hour ago' '+%F %H:%M:%S')"
  END="$(date '+%F %H:%M:%S')"

  # Filtra linhas do iContact no intervalo de tempo
  # Formato do Exim: "YYYY-MM-DD HH:MM:SS ..."
  mapfile -t LINES < <(awk -v s="$START" -v e="$END" '
    $1" "$2>=s && $1" "$2<=e {print}
  ' "$LOG" | grep "__cpanel__service__auth__")

  COUNT="${#LINES[@]}"
  [ "$COUNT" -eq 0 ] && exit 0

  HOURHDR="$(date '+%F %H:00')"
  {
    echo "===== $HOURHDR ====="
    echo "Eventos iContact nesta hora: $COUNT"
    # Top IPs ofensores (falhas de login)
    printf "\nTop IPs (falha de login):\n"
    printf "%s\n" "${LINES[@]}" \
      | grep -oE 'Failed Login Attempts from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | awk '{print $5}' | sort | uniq -c | sort -nr | head || true

    # Top destinatários (para quem o cPanel notificou)
    printf "\nTop destinatários:\n"
    printf "%s\n" "${LINES[@]}" \
      | grep -oE ' for [A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' \
      | awk '{print $2}' | sort | uniq -c | sort -nr | head || true

    # 3 exemplos de assunto (T="[...]")
    printf "\nAmostra de assuntos:\n"
    printf "%s\n" "${LINES[@]}" \
      | sed -n 's/.* T="\([^"]\+\)".*/\1/p' | head -n 3 || true
    echo
  } >> "$DIGEST"
}

send_daily() {
  RECIPIENT="$1"
  [ -z "$RECIPIENT" ] && { echo "Informe o e-mail de destino."; exit 1; }

  if [ ! -s "$DIGEST" ]; then
    echo "Sem eventos hoje. Nada a enviar."
    exit 0
  fi

  SUBJECT="[Digest cPanel iContact] $TODAY — resumo diário"
  BODY_FILE="$WORKDIR/body-$TODAY.txt"

  {
    echo "Resumo diário de alertas do cPanel (iContact) — $TODAY"
    echo
    echo "Total de linhas no Exim referentes ao iContact hoje:"
    grep "__cpanel__service__auth__" "$LOG" | grep "$TODAY" | wc -l
    echo
    echo "==== Consolidado por hora ===="
    cat "$DIGEST"
    echo
    echo "==== Top 20 IPs do dia ===="
    grep "__cpanel__service__auth__" "$LOG" | grep "$TODAY" \
      | grep -oE 'Failed Login Attempts from ([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | awk '{print $5}' | sort | uniq -c | sort -nr | head -n 20 || true
    echo
    echo "Fim do relatório."
  } > "$BODY_FILE"

  # Envia via mailx ou sendmail (fallback)
  if command -v mail >/dev/null 2>&1; then
    mail -s "$SUBJECT" "$RECIPIENT" < "$BODY_FILE"
  else
    {
      echo "Subject: $SUBJECT"
      echo "To: $RECIPIENT"
      echo "Content-Type: text/plain; charset=UTF-8"
      echo
      cat "$BODY_FILE"
    } | /usr/sbin/sendmail -t
  fi

  # Limpa digest do dia
  rm -f "$DIGEST" "$BODY_FILE"
}

case "$1" in
  collect) collect_hour ;;
  send)    send_daily "$2" ;;
  *) echo "Uso: $0 {collect|send <destinatario@dominio>}"; exit 1 ;;
esac


# Coleta a cada hora (minuto 5)
# 5 * * * * /root/cpanel_icontact_digest.sh collect

# Envia 1 e-mail diário às 23:55
# 55 23 * * * /root/cpanel_icontact_digest.sh send seuemail@dominio.com


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/cpanel_icontact_digest.sh") collect
# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/cpanel_icontact_digest.sh") send seuemail@dominio.com