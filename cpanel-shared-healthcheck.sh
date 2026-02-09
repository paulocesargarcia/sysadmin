#!/usr/bin/env bash
set -euo pipefail

RELATORIO="healthcheck_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

# read -d '' retorna 1 ao encontrar EOF (sem NUL); com set -e o script sairia aqui
read -r -d '' COMANDOS <<'EOF' || true
Hostname | hostname
Versão do kernel | uname -a
Sistema operacional | cat /etc/os-release
Data | date
Load average do sistema | uptime
CPU por core | mpstat -P ALL
Uso geral de CPU/memória/IO | vmstat 1 5
Memória RAM e swap | free -h
Swap ativa | swapon --show
Top CPU | ps aux --sort=-%cpu | head
Top memória | ps aux --sort=-%mem | head
Espaço em disco | df -h
Inodes | df -ih
IO e latência de disco | iostat -xz 1 3
Top IO por processo | command -v iotop >/dev/null && iotop -b -n 3 || echo "iotop não instalado"
Dispositivos de bloco | lsblk
Parâmetros kernel críticos | sysctl vm.swappiness fs.file-max net.core.somaxconn
Limites do sistema | ulimit -a
Versão do Apache | httpd -v
MPM e módulos Apache | apachectl -M
Vhosts ativos | apachectl -S
MPM Apache | httpd -V | grep -i mpm
MaxRequestWorkers | grep -R "MaxRequestWorkers" /usr/local/apache/conf
Processos Apache | ps aux | grep httpd | grep -v grep
Versão PHP CLI | php -v
Versões PHP instaladas | whmapi1 php_get_installed_versions
PHP padrão | whmapi1 php_get_system_default_version
memory_limit PHP | grep -R "memory_limit" /opt/cpanel/ea-php*/root/etc/php.ini
post_max_size PHP | grep -R "post_max_size" /opt/cpanel/ea-php*/root/etc/php.ini
upload_max_filesize PHP | grep -R "upload_max_filesize" /opt/cpanel/ea-php*/root/etc/php.ini
max_execution_time PHP | grep -R "max_execution_time" /opt/cpanel/ea-php*/root/etc/php.ini
max_input_vars PHP | grep -R "max_input_vars" /opt/cpanel/ea-php*/root/etc/php.ini
zlib.output_compression PHP | grep -R "zlib.output_compression" /opt/cpanel/ea-php*/root/etc/php.ini
display_errors PHP | grep -R "display_errors" /opt/cpanel/ea-php*/root/etc/php.ini
file_uploads PHP | grep -R "file_uploads" /opt/cpanel/ea-php*/root/etc/php.ini
allow_url_fopen PHP | grep -R "allow_url_fopen" /opt/cpanel/ea-php*/root/etc/php.ini
allow_url_include PHP | grep -R "allow_url_include" /opt/cpanel/ea-php*/root/etc/php.ini
Status MariaDB | systemctl status mariadb || systemctl status mysql
Threads e queries | mysqladmin processlist
Status resumido MySQL | mysqladmin status
Config MySQL (essencial) | mysql -e "SHOW VARIABLES WHERE Variable_name IN ('innodb_buffer_pool_size','innodb_buffer_pool_instances','innodb_log_file_size','innodb_flush_log_at_trx_commit','max_connections','thread_cache_size');" 2>/dev/null || echo "MySQL indisponível"
Status MySQL (essencial) | mysql -e "SHOW GLOBAL STATUS WHERE Variable_name IN ('Threads_connected','Threads_running','Max_used_connections','Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests');" 2>/dev/null || echo "MySQL indisponível"
Conexões de rede | ss -s
Portas abertas | ss -lntup
Total de contas cPanel | whmapi1 listaccts |grep user| wc -l
Load average | cat /proc/loadavg
Uso LVE (CloudLinux) | lveinfo 
Erro Apache | tail -n 50 /usr/local/apache/logs/error_log
Erro cPanel | tail -n 50 /usr/local/cpanel/logs/error_log
Mensagens kernel | dmesg | tail -n 50
EOF

echo "Relatório de Tuning - $(date)" > "$RELATORIO"
echo "===================================" >> "$RELATORIO"

while IFS='|' read -r DESC CMD; do
  echo -e "\n## $DESC" >> "$RELATORIO"
  echo "Comando: $CMD" >> "$RELATORIO"
  echo "-----------------------------------" >> "$RELATORIO"
  eval "$CMD" >> "$RELATORIO" 2>&1 || echo "Erro ao executar comando" >> "$RELATORIO"
done <<< "$COMANDOS"



# Upload para tmptext.com (falha de rede não interrompe o script)
curl -F "file=@$RELATORIO" https://tmptext.com/api/upload  
echo "Relatório gerado em $RELATORIO"
# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-shared-healthcheck.sh")
