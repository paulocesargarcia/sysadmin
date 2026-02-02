#!/bin/bash

# ===============================================================
# NOME: cpanel-health-check.sh
# DESCRIÇÃO: Diagnóstico Especialista de Performance e Integridade
# LOG: Gera saída na tela e em arquivo .log
# ===============================================================

# Definição do arquivo de log
LOG_FILE="health_check_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

# Função para enviar saída para tela e arquivo simultaneamente
exec > >(tee -i "$LOG_FILE") 2>&1

clear
echo "==============================================================="
echo "       RELATÓRIO TÉCNICO DE SAÚDE DO SERVIDOR"
echo "==============================================================="

# --- 1. CABEÇALHO DE IDENTIFICAÇÃO ---
echo -e "\n[1. IDENTIFICAÇÃO DO SISTEMA]"
echo "  Hostname:          $(hostname)"
echo "  Data da Análise:   $(date '+%d/%m/%Y %H:%M:%S')"
echo "  Uptime:            $(uptime -p 2>/dev/null || uptime)"
echo "  SO Version:        $(cat /etc/redhat-release 2>/dev/null || (grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2))"
echo "  Kernel:            $(uname -r)"
echo "  cPanel Version:   $(/usr/local/cpanel/cpanel -V 2>/dev/null)"
echo "  IP Principal:     $(hostname -I 2>/dev/null | awk '{print $1}')"

# --- 2. RECURSOS E CARGA (LOAD) ---
echo -e "\n[2. RECURSOS E CARGA (LOAD)]"
echo "  CPU (Núcleos):   $(nproc)"
echo "  Load Average:    $(cat /proc/loadavg)"
echo ""
echo "  --- Memória RAM ---"
free -h | sed 's/^/  /'
# Swap em destaque (uso alto = possível degradação de performance)
SWAP_USED=$(free -b 2>/dev/null | awk '/^Swap:/{print $3}')
SWAP_TOTAL=$(free -b 2>/dev/null | awk '/^Swap:/{print $2}')
if [ -n "$SWAP_TOTAL" ] && [ "${SWAP_TOTAL:-0}" -gt 0 ]; then
  SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
  if [ "$SWAP_PCT" -gt 50 ]; then
    SWAP_STATUS="ATENÇÃO (${SWAP_PCT}% usado)"
  elif [ "$SWAP_PCT" -gt 0 ]; then
    SWAP_STATUS="Em uso (${SWAP_PCT}%)"
  else
    SWAP_STATUS="OK (sem uso)"
  fi
  echo "  Swap:            $SWAP_STATUS"
fi
echo ""
echo "  --- Armazenamento (espaço em disco) ---"
df -h | grep -E '^Filesystem|/$|/var|/home|/usr' | sed 's/^/  /'
echo ""
echo "  --- Inodes (partições principais) ---"
df -i | grep -E '^Filesystem|/$|/var|/home|/usr' | sed 's/^/  /'
echo ""
echo "  --- Fila de e-mail (Exim) ---"
EXIM_QUEUE=$(exim -bpc 2>/dev/null || echo "0")
printf "  Mensagens na fila: %s\n" "$EXIM_QUEUE"
if [ "${EXIM_QUEUE:-0}" -gt 100 ]; then
  echo "  Status:          ATENÇÃO (fila alta)"
elif [ "${EXIM_QUEUE:-0}" -gt 10 ]; then
  echo "  Status:          Observar"
else
  echo "  Status:           OK"
fi
echo ""
echo "  --- I/O de disco (resumo) ---"
if command -v iostat &>/dev/null; then
  iostat -x 1 2 2>/dev/null | tail -n +4 | sed 's/^/  /'
else
  echo "  (iostat não instalado; use: yum install sysstat)"
  vmstat 1 2 2>/dev/null | sed 's/^/  /'
fi

# --- 3. SERVIÇOS CRÍTICOS E CPANEL ---
# Prioridade: WHM API servicestatus (documentação oficial cPanel); fallback por processo (mysqld, cpsrvd, etc.)
echo -e "\n[3. STATUS DOS SERVIÇOS]"
SERVICESTATUS_PRINTED=0
if command -v whmapi1 &>/dev/null && [ "$(id -u)" -eq 0 ]; then
    RAW=$(whmapi1 servicestatus --output=json 2>/dev/null)
    if [ -n "$RAW" ] && echo "$RAW" | grep -q '"service"'; then
        if command -v jq &>/dev/null; then
            # API: display_name, running (1/0); só listar habilitados, instalados e monitorados pelo WHM
            LINES=$(echo "$RAW" | jq -r '.data.service[]? | select((.enabled // 1) == 1 and (.installed // 1) == 1 and (.monitored // 1) == 1) | "\(.display_name // .displayname // .name | tostring):\(.running // 0)"' 2>/dev/null)
            if [ -n "$LINES" ]; then
                echo "$LINES" | while IFS=: read -r name running; do
                    [ -z "$name" ] && continue
                    if [ "${running:-0}" = "1" ]; then
                        out="RODANDO"
                    else
                        out="FALHOU / PARADO"
                    fi
                    printf "  %-40s: %s\n" "${name:0:40}" "$out"
                done
                SERVICESTATUS_PRINTED=1
            fi
        elif command -v python3 &>/dev/null; then
            LINES=$(echo "$RAW" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for s in d.get('data', {}).get('service', []):
        if s.get('enabled', 1) != 1 or s.get('installed', 1) != 1 or s.get('monitored', 1) != 1:
            continue
        name = (s.get('display_name') or s.get('displayname') or s.get('name') or '?').strip()
        running = 1 if s.get('running', 0) == 1 else 0
        out = 'RODANDO' if running else 'FALHOU / PARADO'
        print('{}:{}'.format(name[:40], out))
except Exception:
    pass
" 2>/dev/null)
            if [ -n "$LINES" ]; then
                echo "$LINES" | while IFS=: read -r name out; do
                    printf "  %-40s: %s\n" "$name" "$out"
                done
                SERVICESTATUS_PRINTED=1
            fi
        fi
    fi
fi
if [ "$SERVICESTATUS_PRINTED" -eq 0 ]; then
    # Fallback: nomes reais dos daemons (MySQL=mysqld, cPanel=cpsrvd)
    check_service() {
        local label="$1"
        shift
        local found=0
        for proc in "$@"; do
            if pgrep -x "$proc" &>/dev/null || pgrep -f "$proc" &>/dev/null; then
                found=1
                break
            fi
        done
        printf "  %-15s: %s\n" "$label" "$([ "$found" -eq 1 ] && echo "RODANDO" || echo "FALHOU / PARADO")"
    }
    check_service "httpd" "httpd"
    check_service "mysql" "mysqld" "mariadbd"
    check_service "php-fpm" "php-fpm"
    check_service "cpanel" "cpsrvd"
    check_service "tailwatchd" "tailwatchd"
    check_service "exim" "exim"
    check_service "named" "named"
    check_service "dovecot" "dovecot"
    check_service "crond" "crond"
    check_service "sshd" "sshd"
    check_service "ftpd" "pure-ftpd" "proftpd"
fi

# --- 4. ANÁLISE PHP-FPM E WEB ---
echo -e "\n[4. CONFIGURAÇÃO E PERFORMANCE PHP-FPM]"
echo "  Versão PHP (CLI):  $(php -v | head -n 1)"
echo "  Limites max_children por pool:"
grep -r "pm.max_children" /opt/cpanel/ea-php*/root/etc/php-fpm.d/ 2>/dev/null | grep -vE '\.(default|example)' | awk -F: '{print "    " $1 " -> " $2}' | sed 's/\/opt\/cpanel\///g'

# --- 5. BANCO DE DADOS (MySQL/MariaDB) ---
echo -e "\n[5. ESTATÍSTICAS DO BANCO DE DADOS]"
if mysqladmin ping &>/dev/null; then
    MYSQL_CURR=$(mysql -N -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
    MYSQL_MAX=$(mysql -N -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
    printf "  Conexões MySQL:   %s / %s (máximo)\n" "${MYSQL_CURR:-?}" "${MYSQL_MAX:-?}"
    if [ -n "$MYSQL_MAX" ] && [ -n "$MYSQL_CURR" ] && [ "$MYSQL_MAX" -gt 0 ]; then
        MYSQL_PCT=$((MYSQL_CURR * 100 / MYSQL_MAX))
        if [ "$MYSQL_PCT" -ge 80 ]; then
            echo "  Status:           ATENÇÃO (próximo do limite)"
        elif [ "$MYSQL_PCT" -ge 50 ]; then
            echo "  Status:           Observar"
        else
            echo "  Status:            OK"
        fi
    fi
    echo ""
    mysqladmin proc stat | sed 's/^/  /'
else
    echo "  ERRO: Não foi possível conectar ao MySQL."
fi

# --- 6. REDE E CONEXÕES ATIVAS ---
echo -e "\n[6. CONEXÕES DE REDE]"
echo "  Porta 80 (HTTP):   $(netstat -an 2>/dev/null | grep :80 | grep ESTABLISHED | wc -l) estabelecidas"
echo "  Porta 443 (HTTPS): $(netstat -an 2>/dev/null | grep :443 | grep ESTABLISHED | wc -l) estabelecidas"
echo ""
echo "  --- Top 10 IPs com mais conexões ---"
netstat -antu 2>/dev/null | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10 | sed 's/^/  /'

# --- 7. LOGS DE ERRO RECENTES (PHP-FPM) ---
echo -e "\n[7. ÚLTIMOS ERROS PHP-FPM (Global)]"
tail -n 20 /opt/cpanel/ea-php*/root/usr/var/log/php-fpm/error.log 2>/dev/null | sed 's/^/  /'

# --- 8. PROCESSOS MAIS PESADOS AGORA ---
echo -e "\n[8. TOP 10 PROCESSOS QUE MAIS CONSOMEM CPU/MEM]"
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu 2>/dev/null | head -n 11 | sed 's/^/  /'

echo -e "\n==============================================================="
echo "              FIM DO RELATÓRIO DE DIAGNÓSTICO"
echo "Relatório salvo em: $LOG_FILE"
echo "==============================================================="

# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-health-check.sh")