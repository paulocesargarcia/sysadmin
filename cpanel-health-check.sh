#!/bin/bash

# ===============================================================
# NOMBRE: cpanel-health-check.sh (Versão Universal)
# DESCRIPCIÓN: Diagnóstico de Performance - Compatível com MySQL/MariaDB
# ===============================================================

LOG_FILE="health_check_$(hostname)_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOG_FILE") 2>&1

clear
echo "==============================================================="
echo "       REPORTE TÉCNICO DE SALUD DEL SERVIDOR (SISTEMAS)"
echo "==============================================================="

# --- 1. IDENTIFICACIÓN DO SISTEMA ---
echo -e "\n[1. IDENTIFICACIÓN DO EQUIPO]"
echo "Hostname:          $(hostname)"
echo "Fecha:             $(date '+%d/%m/%Y %H:%M:%S')"
echo "Uptime:            $(uptime -p)"
echo "Versão cPanel:     $(/usr/local/cpanel/cpanel -V 2>/dev/null || echo 'N/A')"

# --- 2. RECURSOS DO SISTEMA ---
echo -e "\n[2. RECURSOS E CARGA]"
LOAD=$(cat /proc/loadavg | awk '{print $1 " " $2 " " $3}')
echo "CPU Cores:         $(nproc)"
echo "Carga (1/5/15):    $LOAD"
free -h | grep "Mem:" | awk '{print "RAM: Total: "$2" | Usado: "$3" | Livre: "$4}'

# --- 3. STATUS DOS SERVIÇOS (REVISADO) ---
echo -e "\n[3. ESTADO DOS SERVIÇOS CRÍTICOS]"

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "$1: \033[0;32mFUNCIONANDO\033[0m"
        return 0
    else
        echo -e "$1: \033[0;31m¡FALLÓ! / PARADO\033[0m"
        return 1
    fi
}

# Verifica Webserver
check_service httpd

# Verifica Banco de Dados (Tenta MariaDB, depois MySQL)
if systemctl is-active --quiet mariadb; then
    echo -e "database: \033[0;32mFUNCIONANDO (MariaDB)\033[0m"
    DB_TYPE="mariadb"
elif systemctl is-active --quiet mysql; then
    echo -e "database: \033[0;32mFUNCIONANDO (MySQL)\033[0m"
    DB_TYPE="mysql"
else
    echo -e "database: \033[0;31m¡FALLÓ! (MySQL/MariaDB parado)\033[0m"
    DB_TYPE="offline"
fi

# Outros serviços cPanel
check_service cpanel
check_service tailwatchd

# --- 4. ANÁLISE DE BANCO DE DADOS ---
echo -e "\n[4. ESTATÍSTICAS DO BANCO DE DADOS]"
if mysqladmin ping &>/dev/null; then
    mysqladmin proc stat | head -n 1
else
    # Tentativa de ver o erro se o ping falhar
    echo "Erro: mysqladmin não responde. Verificando soquete..."
    ls -la /var/lib/mysql/mysql.sock 2>/dev/null || echo "Soquete não encontrado em /var/lib/mysql/"
fi

# --- 5. REDE (TOP 5 CONEXÕES) ---
echo -e "\n[5. TOP 5 IPs CONECTADOS (Portas 80/443)]"
netstat -ant | grep -E ':80|:443' | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 5

# --- 6. RESUMO PARA A API GEMINI (Oculto ou Final) ---
# Este bloco ajuda a IA do Workspace a não cometer erros de leitura
echo -e "\n--- [DADOS_TECNICOS_JSON] ---"
cat <<EOF
{
  "hostname": "$(hostname)",
  "db_status": "$(systemctl is-active mariadb || systemctl is-active mysql)",
  "db_engine": "$DB_TYPE",
  "cpanel_status": "$(systemctl is-active cpanel)",
  "load": "$LOAD",
  "disk_usage": "$(df -h / | awk 'NR==2 {print $5}')"
}
EOF
echo "--- [FIM_DADOS] ---"

echo -e "\n==============================================================="
echo "              DIAGNÓSTICO CONCLUÍDO COM SUCESSO"
echo "==============================================================="