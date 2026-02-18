#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PROMPT PARA ANÁLISE (COPIAR E COLAR JUNTO COM O RELATÓRIO)
# ============================================================
PROMPT_ANALISE="
CONTEXTO E REGRAS:
- Analise este relatório de saúde de um servidor cPanel com hospedagem compartilhada em produção.
- Baseie-se EXCLUSIVAMENTE nos dados e métricas deste relatório; não invente números nem valores que não constem no relatório ou nos arquivos de configuração fornecidos.
- O número aproximado de contas cPanel está informado no relatório; use-o como referência.

VERSÕES E COMPATIBILIDADE (obrigatório):
- Sempre analise e considere as versões informadas no relatório: sistema operacional, distribuição (ex.: AlmaLinux, CloudLinux), versão do cPanel/WHM, Apache, PHP, MySQL/MariaDB e demais software relevantes.
- Recomende sempre considerando as versões mais recentes estáveis compatíveis com o ambiente; não sugira comandos, sintaxe ou opções que não se apliquem à versão do SO, distribuição ou software indicada no relatório.
- Não indique comandos obsoletos ou deprecados para a versão em uso (ex.: evite netstat se o ambiente usar ss; use sintaxe de systemctl e não service quando aplicável à distro do relatório).

COMANDOS A SEREM EXECUTADOS:
- Quando precisar sugerir a execução de comandos (verificação, aplicação de tuning, reinício de serviço), informe cada comando de forma clara, em linha separada, em bloco de código, para copiar e colar.
- Indique em qual contexto executar (ex.: como root, em qual diretório) quando relevante.

ANTES DE RECOMENDAR ALTERAÇÕES:
- Se for sugerir a alteração de um parâmetro e o valor atual NÃO estiver disponível no relatório nem nos arquivos de configuração anexados, SOLICITE ao usuário que informe o valor atual antes de recomendar o novo valor.
- Peça que o usuário anexe ou cole o conteúdo dos arquivos de configuração relevantes (ex.: my.cnf, httpd.conf, php.ini, sysctl.conf, pools PHP-FPM) para que você tenha o máximo de elementos e possa recomendar com precisão. Indique claramente quais arquivos são necessários quando faltarem dados.

ESTRUTURA DA RESPOSTA (obrigatória):
1. Diagnóstico – resumo do estado atual com base nos dados do relatório.
2. Recomendações de tuning – Apache, PHP-FPM, MySQL e SO, em ordem de prioridade: Crítico | Importante | Desejável.
3. Segurança, backup e monitoramento – incluindo endereço IP do servidor ou de endpoints (firewall, monitoramento) quando aplicável.
4. Estimativa de capacidade – clientes simultâneos e carga de trabalho esperada após as melhorias (quando aplicável).
5. Inclua recomendações de LVE (CloudLinux) e Imunify360 quando os dados estiverem no relatório.

FORMATO DAS ALTERAÇÕES DE PARÂMETROS:
Para cada alteração sugerida, apresente em TABELA com três colunas obrigatórias:
| Parâmetro (arquivo) | Valor atual | Valor novo | Justificativa |
Use a coluna \"Valor atual\" com o valor lido do relatório ou dos arquivos enviados; se não tiver o valor, escreva \"SOLICITAR AO USUÁRIO\" e peça o valor antes de preencher \"Valor novo\".

Recomendações de tuning devem especificar: arquivo (caminho completo), parâmetro, valor novo, e justificativa baseada no relatório. Para software, informe nome e versão; para hardware, quantidade e tipo; para rede e segurança, detalhe conforme os dados disponíveis.
"
# ============================================================
# VERIFICAÇÃO DE DEPENDÊNCIAS
# ============================================================
# Lista de softwares/comandos necessários para a execução do script.
# Para adicionar novos requisitos, insira o nome do binário na lista abaixo.
DEPENDENCIAS=(
    "curl"
    "elinks"
    "mpstat"    # pacote: sysstat
    "vmstat"    # pacote: sysstat
    "iostat"    # pacote: sysstat
    "whmapi1"   # pacote: cpanel
    "iotop"     # pacote: sysstat
    "/root/mysqltuner.pl"   # opcional: baixar quando for usar o healthcheck curl -sO https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl
)

verificar_dependencias() {
    local faltantes=()
    echo ">> Verificando dependências..."
    
    for cmd in "${DEPENDENCIAS[@]}"; do
        if [[ "$cmd" == /* ]]; then
            test -f "$cmd" || faltantes+=("$cmd")
        else
            command -v "$cmd" >/dev/null 2>&1 || faltantes+=("$cmd")
        fi
    done

    if [ ${#faltantes[@]} -gt 0 ]; then
        echo "----------------------------------------------------------------"
        echo "ERRO: Foram detectadas dependências ausentes."
        echo "O script não pode continuar sem os seguintes comandos:"
        echo ""
        for cmd in "${faltantes[@]}"; do
            echo "  [X] $cmd"
        done
        echo ""
        echo "Sugestão de instalação (AlmaLinux/CloudLinux):"
        echo "  dnf -y install elinks sysstat"
        echo "----------------------------------------------------------------"
        exit 1
    fi
    
    echo ">> Todas as dependências foram encontradas."
}

# Executa a verificação antes de prosseguir
verificar_dependencias

RELATORIO="healthcheck_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

# read -d '' retorna 1 ao encontrar EOF (sem NUL); com set -e o script sairia aqui
read -r -d '' COMANDOS <<'EOF' || true
Data | date
Hostname | hostname
Versão do kernel | uname -a
Sistema operacional | cat /etc/os-release
cPanel/WHM version | whmapi1 version | grep -E "version|release"
Imunify360 version | imunify360-agent version
Apache version | httpd -V
Versões PHP (EA4) | ls /opt/cpanel/ | grep ea-php
Versão PHP CLI | php -v
MySQL/MariaDB version | mysql --version || mariadb --version
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
Top IO por processo | command -v iotop >/dev/null && iotop -b -n 3 -o || echo "iotop não instalado"
Dispositivos de bloco | lsblk
Parâmetros kernel críticos | sysctl vm.swappiness fs.file-max net.core.somaxconn
Limites do sistema | ulimit -a
Tamanho medio de processo Apache | ps -ylC httpd --sort:rss | awk 'NR!=1 {print $8 / 1024}'
MPM e módulos Apache | apachectl -M
Processos Apache | ps aux | grep httpd | grep -v grep
Apachectl fullstatus | apachectl fullstatus
PHP padrão | whmapi1 php_get_system_default_version
Pools PHP-FPM | for d in /opt/cpanel/ea-php*/root/etc/php-fpm.d; do v="${d#/opt/cpanel/}"; v="${v%%/*}"; echo ""; echo "[$v]"; grep -h -E "^(pm\.max_children|pm\.start_servers|pm\.min_spare_servers|pm\.max_spare_servers|memory_limit)[[:space:]]*=" "$d"/*.conf 2>/dev/null || true; done
Parâmetros php.ini por versão | for f in /opt/cpanel/ea-php*/root/etc/php.ini; do v="${f#/opt/cpanel/}"; v="${v%%/*}"; echo ""; echo "[$v]"; grep -v "^[[:space:]]*;" "$f" 2>/dev/null | grep -E "^[[:space:]]*(memory_limit|post_max_size|upload_max_filesize|max_execution_time|max_input_vars|zlib\.output_compression|display_errors|file_uploads|allow_url_fopen|allow_url_include)[[:space:]]*=" || true; done
Status MariaDB | systemctl status mariadb || systemctl status mysql
Threads e queries | mysqladmin processlist
Status resumido MySQL | mysqladmin extended-status
Parâmetros MySQL/MariaDB | for f in /etc/my.cnf /etc/my.cnf.d/*.cnf; do echo ""; echo "[$f]"; grep -v "^[[:space:]]*;" "$f" 2>/dev/null | grep -E "^[[:space:]]*(innodb_buffer_pool_size|max_connections|thread_cache_size|tmp_table_size|max_heap_table_size)[[:space:]]*=" || true; done
Conexões de rede | ss -s
Portas abertas | ss -lntup
Total de contas cPanel | whmapi1 listaccts |grep user| wc -l
Uso LVE (CloudLinux) | command -v lveinfo >/dev/null && lveinfo || echo "CloudLinux não instalado (LVE não disponível)"
Global PHP-FPM defaults | grep -E "pm_max_children|pm_max_requests|pm_process_idle_timeout" /var/cpanel/ApachePHPFPM/system_pool_defaults.yaml
Apache httpd.conf | egrep 'ServerLimit|ThreadsPerChild|MaxRequestWorkers|MaxConnectionsPerChild|KeepAlive|MaxKeepAliveRequests|KeepAliveTimeout' /etc/apache2/conf/httpd.conf
LimitNOFILE Apache | grep -R "LimitNOFILE" /etc/systemd/system /usr/lib/systemd/system/httpd.service
LVE defaults | command -v lvectl >/dev/null && lvectl list || echo "CloudLinux não instalado (lvectl não disponível)"
Config Imunify360 | imunify360-agent config show
Erro Apache | tail -n 50 /usr/local/apache/logs/error_log
Erro cPanel | tail -n 50 /usr/local/cpanel/logs/error_log
Mensagens kernel | dmesg | tail -n 50
MySQL Tuner | test -f /root/mysqltuner.pl && perl /root/mysqltuner.pl 2>&1 || echo "MySQLTuner não encontrado (/root/mysqltuner.pl)"
EOF

echo "Relatório de Tuning - $(date)" > "$RELATORIO"
echo "===================================" >> "$RELATORIO"

while IFS='|' read -r DESC CMD; do
  echo -e "\n## $DESC" 
  echo -e "\n## $DESC" >> "$RELATORIO"
  echo "Comando: $CMD" >> "$RELATORIO"
  echo "-----------------------------------" >> "$RELATORIO"
  eval "$CMD" >> "$RELATORIO" 2>&1 || echo "Erro ao executar comando" >> "$RELATORIO"
done <<< "$COMANDOS"

echo "Relatório gerado em $RELATORIO"

# Upload para tmptext.com – resposta JSON formatada (falha de rede não interrompe o script)
RESP=$(curl -s -F "file=@$RELATORIO" https://tmptext.com/api/upload) || true
if [[ -n "$RESP" && "$RESP" =~ \"url\" ]]; then
  URL=$(echo "$RESP" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
  EXPIRE_RAW=$(echo "$RESP" | sed -n 's/.*"expires_at":"\([^"]*\)".*/\1/p')
  EXPIRE=$(echo "$EXPIRE_RAW" | awk -F- '{print $3"/"$2"/"$1}')
  echo "URL: $URL"
  echo "EXPIRE: $EXPIRE"
else
  echo "Upload opcional falhou; relatório local em $RELATORIO"
fi


# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-shared-healthcheck.sh")
