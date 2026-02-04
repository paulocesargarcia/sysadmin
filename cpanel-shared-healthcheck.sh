#!/bin/bash

# ============================================================
# PROMPT PARA ANÁLISE (COPIAR E COLAR JUNTO COM O RELATÓRIO)
# ============================================================
# "Analise este relatório de saúde de um servidor cPanel com hospedagem compartilhada.
# O servidor possui aproximadamente este número de contas informado no relatório.
# Gere recomendações de tuning para Apache, PHP-FPM, MySQL e SO considerando ambiente
# shared hosting em produção."
# ============================================================

mkdir -p /root/healthcheck
REPORT="/root/healthcheck/health_report_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

exec > "$REPORT" 2>&1

echo "============================================================"
echo "RELATÓRIO DE SAÚDE – SERVIDOR CPANEL (SHARED)"
echo "============================================================"

echo "\n[1] IDENTIFICAÇÃO DO SISTEMA"
hostnamectl
echo "Data: $(date)"
uptime

echo "
[1A] SISTEMA OPERACIONAL E KERNEL"
cat /etc/os-release
uname -a


echo "
[1B] HARDWARE"
lsmem 2>/dev/null || true
lsipc 2>/dev/null || true


echo "
[1C] CPU DETALHADO"
lscpu
grep -E "processor|core id|cpu MHz" /proc/cpuinfo | head


echo "
[1D] MEMÓRIA DETALHADA"
cat /proc/meminfo | head -n 20


echo "
[1E] VIRTUALIZAÇÃO"
(systemd-detect-virt || virt-what) 2>/dev/null || echo "Não detectado"


echo "
[1F] TEMPO DE ATIVIDADE DETALHADO"
who -a


# ------------------------------------------------------------
echo "\n[2] CONTAS CPANEL"
if command -v whmapi1 &>/dev/null; then
  echo "Total de contas (whmapi1):"
  whmapi1 listaccts | grep -c "user:"
else
  echo "Total de contas (/var/cpanel/users):"
  ls /var/cpanel/users 2>/dev/null | wc -l
fi

# ------------------------------------------------------------
echo "\n[3] CPU"
lscpu
mpstat -P ALL 1 3

# ------------------------------------------------------------
echo "\n[4] MEMÓRIA E SWAP"
free -h
vmstat 1 3
swapon --show

# ------------------------------------------------------------
echo "
[5] DISCO / I-O"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
blkid
df -hT
df -i
iostat -x 1 3

# ------------------------------------------------------------
echo "\n[6] LOAD"
uptime

# ------------------------------------------------------------
echo "
[7] REDE"
ss -s
ip addr show
ip route
sar -n TCP,ETCP 1 3


echo "
[7A] TOP IPs CONECTADOS"
netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head

# ------------------------------------------------------------
echo "
[8] APACHE"
httpd -V | grep -i mpm
apachectl -M | egrep "mpm|rewrite|expires|headers"
grep -R "MaxRequestWorkers" /etc/apache2 2>/dev/null
ps -eo pid,user,%cpu,%mem,cmd | grep httpd | grep -v grep | head

# ------------------------------------------------------------
echo "
[9] PHP-FPM – POOLS E CONSUMO"
ls /opt/cpanel/ea-php*/root/etc/php-fpm.d 2>/dev/null | wc -l


echo "Pools e limites:" 
grep -R "pm.max_children" /opt/cpanel/ea-php*/root/etc/php-fpm.d 2>/dev/null | sort | uniq | head


echo "Top PHP-FPM por consumo:" 
ps -eo user,%cpu,%mem,cmd | grep php-fpm | grep -v root | sort -k2 -nr | head


echo "Versões PHP instaladas:" 
ls -d /opt/cpanel/ea-php* | sed 's#.*/##'

ps -eo user,%cpu,%mem,cmd | grep php-fpm | grep -v root | sort -k2 -nr | head

# ------------------------------------------------------------
echo "
[10] MYSQL / MARIADB"
mysqladmin status 2>/dev/null
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_running';" 2>/dev/null
mysql -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null
mysql -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null
ps -eo pid,%cpu,%mem,cmd | grep mariadbd | grep -v grep

# ------------------------------------------------------------
echo "\n[11] TOP PROCESSOS GERAIS"
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head

# ------------------------------------------------------------
echo "
[12] SERVIÇOS PRINCIPAIS"
systemctl --type=service --state=running | egrep "httpd|php-fpm|mariadb|exim|redis|memcached" || true


echo "
[12A] SERVIÇOS FALHOS"
systemctl --failed

# ------------------------------------------------------------
echo "
[13] KERNEL / SYSCTL RELEVANTE"
sysctl vm.swappiness
sysctl fs.file-max
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_fin_timeout
sysctl net.ipv4.tcp_tw_reuse

# ------------------------------------------------------------
echo "\nFIM DO RELATÓRIO"
echo "Arquivo gerado em: $REPORT"

echo "Enviando relatório para o tmptext.com..."
curl -F "file=@$REPORT" https://tmptext.com/api/upload

# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-shared-healthcheck.sh")