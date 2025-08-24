#!/usr/bin/env bash
# Auditoria de envio de spam em servidores cPanel/Exim
# Uso:
#   sudo bash cpanel_exim_spam_audit.sh
#   DAYS=3 sudo -E bash cpanel_exim_spam_audit.sh   # janela maior
set -euo pipefail

OUT="/root/cpanel_exim_spam_audit_$(date +%F_%H%M).txt"
DAYS="${DAYS:-2}"
SUS_IPS="${SUS_IPS:-117.46.7.40|117.46.7.39}"  # IPs citados

log() { echo -e "$@" | tee -a "$OUT"; }
sec() { log "\n=== $1 ==="; }

: > "$OUT"
log "=== AUDITORIA cPanel/Exim ($(date)) ==="
log "Relatório: $OUT"

MAINLOG="/var/log/exim_mainlog"
REJLOG="/var/log/exim_rejectlog"

if ! command -v exim >/dev/null; then
  log "ERRO: Exim não encontrado."; exit 1
fi

# ---- 1) Info do sistema / cPanel ----
sec "1) Sistema e cPanel"
uname -a | tee -a "$OUT"
[ -x /usr/local/cpanel/cpanel ] && log "cPanel: instalado" || log "cPanel: não detectado"
exim -bV 2>/dev/null | head -n 1 | tee -a "$OUT"

# ---- 2) Fila Exim ----
sec "2) Fila do Exim (resumo)"
QUEUE_CT=$(exim -bpc || echo 0)
log "Mensagens na fila: $QUEUE_CT"
exim -bp | head -n 200 | tee -a "$OUT" || true

# ---- 3) Top remetentes / SASL / scripts via log ----
sec "3) Atividade por usuários autenticados (SASL), últimos $DAYS dia(s)"
if [ -f "$MAINLOG" ]; then
  # extrai janela por data aproximando por 'date -d'
  SINCE=$(date --date="-$DAYS days" "+%Y-%m-%d")
  awk -v since="$SINCE" '$0 ~ since,0' "$MAINLOG" > /tmp/exim.win || true

  log "- SASL (dovecot_login/plain) mais ativos:"
  grep -Eo 'A=dovecot_(login|plain):[^ ]+' /tmp/exim.win \
    | cut -d: -f2 | sort | uniq -c | sort -rn | head -n 25 | tee -a "$OUT" || true

  log "- FROM mais ativos:"
  grep ' <=' /tmp/exim.win \
    | awk '{for(i=1;i<=NF;i++) if($i~/^F=</){sub(/^F=</,"",$i); sub(/>$/,"",$i); print tolower($i)}}' \
    | sort | uniq -c | sort -rn | head -n 25 | tee -a "$OUT" || true

  log "- Scripts PHP que chamaram sendmail (cwd em /home):"
  grep -E 'cwd=/home/.+ public_html|cwd=/home/.+' /tmp/exim.win \
    | grep -E 'U=[a-z0-9]+' | awk '{print $0}' | head -n 200 | tee -a "$OUT" || true

  log "- Caminhos de script (cwd) com maior volume:"
  grep -Eo 'cwd=/home/[^ ]+' /tmp/exim.win \
    | sort | uniq -c | sort -rn | head -n 25 | tee -a "$OUT" || true

  log "- Destinos suspeitos (IPs citados):"
  grep -E "$SUS_IPS" /tmp/exim.win | head -n 200 | tee -a "$OUT" || true

  rm -f /tmp/exim.win
else
  log "Log não encontrado: $MAINLOG"
fi

# ---- 4) Estatísticas rápidas com eximstats ----
sec "4) eximstats (visão geral rápida)"
if command -v eximstats >/dev/null && [ -f "$MAINLOG" ]; then
  # reduzir carga: analisar somente parte recente do log
  tail -n 200000 "$MAINLOG" > /tmp/exim.tail || true
  eximstats /tmp/exim.tail | sed -n '1,160p' | tee -a "$OUT" || true
  rm -f /tmp/exim.tail
else
  log "eximstats indisponível ou $MAINLOG ausente."
fi

# ---- 5) Rejeições/erros frequentes ----
sec "5) Rejeições mais comuns (rejectlog), últimos $DAYS dia(s)"
if [ -f "$REJLOG" ]; then
  SINCE=$(date --date="-$DAYS days" "+%Y-%m-%d")
  awk -v since="$SINCE" '$0 ~ since,0' "$REJLOG" \
    | awk -F': ' '{print $NF}' | cut -d' ' -f1-8 \
    | sort | uniq -c | sort -rn | head -n 30 | tee -a "$OUT" || true
else
  log "Log não encontrado: $REJLOG"
fi

# ---- 6) Scan rápido por mailers PHP suspeitos ----
sec "6) Scan em public_html por funções críticas (últimos $DAYS dia[s])"
for W in /home/*/public_html; do
  [ -d "$W" ] || continue
  echo "Diretório: $W" | tee -a "$OUT"
  find "$W" -type f -name '*.php' -mtime -"$DAYS" -print0 2>/dev/null \
    | xargs -0 grep -HnE 'mail\(|base64_decode\(|shell_exec\(|passthru\(|eval\(|assert\(' 2>/dev/null \
    | tee -a "$OUT" || true
done

# ---- 7) Cronjobs cPanel ----
sec "7) Cronjobs de usuários cPanel"
for U in /var/spool/cron/*; do
  [ -f "$U" ] || continue
  USR="$(basename "$U")"
  echo "CRON de $USR:" | tee -a "$OUT"
  sed 's/^/  /' "$U" | tee -a "$OUT"
done
echo "CRON do root:" | tee -a "$OUT"
[ -f /var/spool/cron/root ] && sed 's/^/  /' /var/spool/cron/root | tee -a "$OUT" || true

# ---- 8) Dicas e ações seguras ----
sec "8) Dicas (NÃO executadas automaticamente)"
cat >> "$OUT" <<'HINTS'
[Análise]
- Procure: SASL user com muitos envios; linhas 'cwd=' apontando para script em /home/USER/public_html; picos na fila.
- Se script suspeito: isole o arquivo, compare com backup, atualize CMS/plugins.

[Comandos úteis]
- Listar IDs da fila com assunto:
    exim -bp | exiqgrep -i | xargs -I{} sh -c 'echo "--- {} ---"; exim -Mvh {} | egrep -i "Subject|From|Received" | sed "s/^/   /"'
- Remover TODA a fila (cautela):
    exim -bp | exiqgrep -i | xargs exim -Mrm
- Remover fila por remetente:
    exiqgrep -f 'usuario@dominio' -i | xargs exim -Mrm

[Mitigações no cPanel/WHM]
- Ative "SMTP Restrictions" e "Restrict outgoing SMTP" (WHM » Security Center).
- Configure "Max hourly emails per domain" (WHM » Tweak Settings).
- Use "Mail > Mail Delivery Reports" e "Mail > Mail Queue Manager" no WHM para investigar.
- Considere usar Smart Host (relay) autenticado e manter porta 25 bloqueada externamente.

HINTS

sec "9) Concluído"
log "Relatório salvo em: $OUT"


# sudo bash cpanel_exim_spam_audit.sh
# (opcional) aumentar janela de análise:
# DAYS=7 sudo -E bash cpanel_exim_spam_audit.sh

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/cpanel_exim_spam_audit.sh")