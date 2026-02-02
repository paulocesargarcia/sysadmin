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
echo "Hostname:          $(hostname)"
echo "Data da Análise:   $(date '+%d/%m/%Y %H:%M:%S')"
echo "Uptime:            $(uptime -p)"
echo "SO Version:        $(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel:            $(uname -r)"
echo "cPanel Version:    $(/usr/local/cpanel/cpanel -V)"
echo "IP Principal:      $(hostname -I | awk '{print $1}')"

# --- 2. RECURSOS DE HARDWARE ---
echo -e "\n[2. RECURSOS E CARGA (LOAD)]"
echo "CPU (Núcleos):     $(nproc)"
echo "Load Average:      $(cat /proc/loadavg)"
echo -e "\n--- Memória RAM ---"
free -h
echo -e "\n--- Armazenamento (Partições principais) ---"
df -h | grep -E '^Filesystem|/$|/var|/home|/usr'

# --- 3. SERVIÇOS CRÍTICOS E CPANEL ---
echo -e "\n[3. STATUS DOS SERVIÇOS]"
for service in httpd mysql php-fpm cpanel tailwatchd; do
    printf "%-15s: " "$service"
    if pgrep -x "$service" > /dev/null || ([ "$service" == "httpd" ] && pgrep -x "httpd" > /dev/null); then
        echo "RODANDO"
    else
        echo "FALHOU / PARADO"
    fi
done

# --- 4. ANÁLISE PHP-FPM E WEB ---
echo -e "\n[4. CONFIGURAÇÃO E PERFORMANCE PHP-FPM]"
echo "Versão PHP (CLI):  $(php -v | head -n 1)"
echo "Limites max_children por pool:"
grep -r "pm.max_children" /opt/cpanel/ea-php*/root/etc/php-fpm.d/ | awk -F: '{print $1 " -> " $2}' | sed 's/\/opt\/cpanel\///g'

# --- 5. BANCO DE DADOS (MySQL/MariaDB) ---
echo -e "\n[5. ESTATÍSTICAS DO BANCO DE DADOS]"
if mysqladmin ping &>/dev/null; then
    mysqladmin proc stat
else
    echo "ERRO: Não foi possível conectar ao MySQL."
fi

# --- 6. REDE E CONEXÕES ATIVAS ---
echo -e "\n[6. CONEXÕES DE REDE]"
echo "Porta 80 (HTTP):   $(netstat -an | grep :80 | grep ESTABLISHED | wc -l) estabelecidas"
echo "Porta 443 (HTTPS): $(netstat -an | grep :443 | grep ESTABLISHED | wc -l) estabelecidas"
echo -e "\n--- Top 10 IPs com mais conexões (Geral) ---"
netstat -antu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10

# --- 7. LOGS DE ERRO RECENTES (PHP-FPM) ---
echo -e "\n[7. ÚLTIMOS ERROS PHP-FPM (Global)]"
tail -n 20 /opt/cpanel/ea-php*/root/usr/var/log/php-fpm/error.log 2>/dev/null

# --- 8. PROCESSOS MAIS PESADOS AGORA ---
echo -e "\n[8. TOP 10 PROCESSOS QUE MAIS CONSOMEM CPU/MEM]"
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 11

echo -e "\n==============================================================="
echo "              FIM DO RELATÓRIO DE DIAGNÓSTICO"
echo "Relatório salvo em: $LOG_FILE"
echo "==============================================================="

# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-health-check.sh")