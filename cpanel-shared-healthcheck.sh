#!/usr/bin/env bash

# ============================================================
# cPanel Shared Hosting Health Check
# Gera relatório completo de saúde do servidor
# ============================================================

set -uo pipefail

# ============================================================
# PROMPT PARA ANÁLISE (COPIAR E COLAR JUNTO COM O RELATÓRIO)
# ============================================================
PROMPT_ANALISE="
  Analise este relatório de saúde de um servidor cPanel com hospedagem compartilhada.
  O servidor possui aproximadamente este número de contas informado no relatório.
  Gere recomendações de tuning para Apache, PHP-FPM, MySQL e SO considerando ambiente shared hosting em produção.
  Justifique as recomendações com base no relatório, em especial as recomendações de tuning.
  Especifique recomendações de tuning (arquivo e valor), software (e versão), hardware (e quantidade), rede, segurança, backup ou monitoramento, incluindo endereço IP quando aplicável.
  Sempre informe as recomendações de forma clara e objetiva e o arquivo que sera alterado ou criado.
  Em seguida, informe uma estimativa de clientes simultaneos e de um estimativa de carga de trabalho, de acordo com as melhorias de tuning recomendadas.
"
# ============================================================

# Variáveis globais
REPORT_DIR="/root/healthcheck"
REPORT=""
SKIP_UPLOAD=0
SECTIONS="all"

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

show_help() {
  cat << EOF
Uso: $(basename "$0") [OPÇÕES]

Gera relatório completo de saúde do servidor cPanel (shared hosting).

OPÇÕES:
  -h, --help              Exibe esta ajuda
  -s, --skip-upload       Não envia relatório para tmptext.com
  -o, --output DIR        Define diretório de saída (padrão: /root/healthcheck)
  -S, --sections LIST     Executa apenas seções específicas (ex: 1,2,3 ou all)

SEÇÕES DISPONÍVEIS:
  1  - Identificação do sistema
  2  - Contas cPanel
  3  - CPU
  4  - Memória e swap
  5  - Disco / I-O
  6  - Load
  7  - Rede
  8  - Apache
  9  - PHP-FPM
  10 - MySQL / MariaDB
  11 - Top processos
  12 - Serviços
  13 - Kernel / sysctl
  14 - CloudLinux / LVE (se disponível)
  15 - Imunify360 (se disponível)
  16 - Arquivos de configuração principais (my.cnf, httpd, php.ini, sysctl, etc.)

EXEMPLOS:
  $(basename "$0")                    # Executa todas as seções
  $(basename "$0") -s                 # Sem upload
  $(basename "$0") -S 1,2,3           # Apenas seções 1, 2 e 3
  $(basename "$0") -o /tmp/reports    # Salva em /tmp/reports

USO REMOTO:
  bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-shared-healthcheck.sh")

EOF
  exit 0
}

log_error() {
  echo "ERRO: $1" >&2
  exit 1
}

log_warning() {
  echo "AVISO: $1" >&2
}

check_dependencies() {
  local deps=("hostname" "date" "grep" "awk" "sed" "ps" "df" "free" "uptime")
  local missing=()
  
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Dependências ausentes: ${missing[*]}"
  fi
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Este script precisa ser executado como root"
  fi
}

check_cpanel() {
  if [[ ! -d /usr/local/cpanel ]]; then
    log_warning "cPanel não detectado em /usr/local/cpanel"
  fi
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]] && [[ -n "${REPORT:-}" ]]; then
    echo "Script interrompido. Relatório parcial salvo em: $REPORT" >&3 2>/dev/null || true
  fi
}

# Guarda o terminal no fd 3 antes de redirecionar stdout/stderr para o relatório
setup_output() {
  exec 3>/dev/tty 2>/dev/null || exec 3>&2
  exec > "$REPORT" 2>&1
}

# Escreve a etapa no terminal (fd 3) com timestamp
step() {
  local timestamp
  timestamp=$(date '+%H:%M:%S')
  echo "[$timestamp] >>> $1" >&3
}

section_header() {
  local section=$1
  local title=$2
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo ""
  echo "============================================================"
  echo "[$section] $title"
  echo "Timestamp: $timestamp"
  echo "============================================================"
}

should_run_section() {
  local section=$1
  
  if [[ "$SECTIONS" == "all" ]]; then
    return 0
  fi
  
  if [[ ",$SECTIONS," == *",$section,"* ]]; then
    return 0
  fi
  
  return 1
}

# ============================================================
# PARSE DE ARGUMENTOS
# ============================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        ;;
      -s|--skip-upload)
        SKIP_UPLOAD=1
        shift
        ;;
      -o|--output)
        REPORT_DIR="$2"
        shift 2
        ;;
      -S|--sections)
        SECTIONS="$2"
        shift 2
        ;;
      *)
        log_error "Opção desconhecida: $1. Use -h para ajuda."
        ;;
    esac
  done
}

# ============================================================
# INICIALIZAÇÃO
# ============================================================

init() {
  check_root
  check_dependencies
  check_cpanel
  
  mkdir -p "$REPORT_DIR" || log_error "Não foi possível criar diretório $REPORT_DIR"
  REPORT="$REPORT_DIR/health_report_$(hostname)_$(date +%Y%m%d_%H%M%S).log"
  
  trap cleanup EXIT INT TERM
  
  setup_output
}

# ============================================================
# SEÇÕES DE COLETA
# ============================================================

section_01_system_identification() {
  if ! should_run_section 1; then return; fi
  
  step "[1] Identificação do sistema"
  section_header "1" "IDENTIFICAÇÃO DO SISTEMA"
  
  hostnamectl 2>/dev/null || {
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
  }
  echo "Data: $(date)"
  uptime
  
  echo ""
  echo "[1A] SISTEMA OPERACIONAL E KERNEL"
  cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || echo "N/A"
  uname -a
  
  echo ""
  echo "[1B] HARDWARE"
  lsmem 2>/dev/null || echo "lsmem não disponível"
  lsipc 2>/dev/null || echo "lsipc não disponível"
  
  echo ""
  echo "[1C] CPU DETALHADO"
  lscpu
  grep -E "processor|core id|cpu MHz" /proc/cpuinfo | head -n 20
  
  echo ""
  echo "[1D] MEMÓRIA DETALHADA"
  head -n 20 /proc/meminfo
  
  echo ""
  echo "[1E] VIRTUALIZAÇÃO"
  systemd-detect-virt 2>/dev/null || virt-what 2>/dev/null || echo "Não detectado"
  
  echo ""
  echo "[1F] TEMPO DE ATIVIDADE DETALHADO"
  who -a 2>/dev/null || w
  
  return 0
}

section_02_cpanel_accounts() {
  if ! should_run_section 2; then return; fi
  
  step "[2] Contas cPanel"
  section_header "2" "CONTAS CPANEL"
  
  if command -v whmapi1 &>/dev/null; then
    echo "Total de contas (whmapi1):"
    whmapi1 listaccts 2>/dev/null | grep -c "user:" || echo "Erro ao consultar whmapi1"
  else
    echo "Total de contas (/var/cpanel/users):"
    find /var/cpanel/users -maxdepth 1 -type f 2>/dev/null | wc -l
  fi
  
  echo ""
  echo "Contas suspensas:"
  grep -l "SUSPENDED=1" /var/cpanel/users/* 2>/dev/null | wc -l || echo "0"
  
  return 0
}

section_03_cpu() {
  if ! should_run_section 3; then return; fi
  
  step "[3] CPU"
  section_header "3" "CPU"
  
  lscpu || echo "Erro ao executar lscpu"
  
  if command -v mpstat &>/dev/null; then
    echo ""
    echo "Estatísticas por CPU (3 amostras):"
    mpstat -P ALL 1 3 || echo "Erro ao executar mpstat"
  else
    echo ""
    echo "mpstat não disponível (instale sysstat)"
  fi
  
  return 0
}

section_04_memory() {
  if ! should_run_section 4; then return; fi
  
  step "[4] Memória e swap"
  section_header "4" "MEMÓRIA E SWAP"
  
  free -h || echo "Erro ao executar free"
  
  echo ""
  echo "Estatísticas vmstat (3 amostras):"
  vmstat 1 3 || echo "Erro ao executar vmstat"
  
  echo ""
  echo "Swap ativo:"
  swapon --show 2>/dev/null || echo "Nenhum swap ativo"
  
  return 0
}

section_05_disk() {
  if ! should_run_section 5; then return; fi
  
  step "[5] Disco / I-O"
  section_header "5" "DISCO / I-O"
  
  echo "Dispositivos de bloco:"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || echo "lsblk não disponível"
  
  echo ""
  echo "UUIDs dos dispositivos:"
  blkid 2>/dev/null || echo "blkid não disponível"
  
  echo ""
  echo "Uso de disco por filesystem:"
  df -hT || echo "Erro ao executar df"
  
  echo ""
  echo "Uso de inodes:"
  df -i || echo "Erro ao executar df -i"
  
  if command -v iostat &>/dev/null; then
    echo ""
    echo "Estatísticas I/O (3 amostras):"
    iostat -x 1 3 || echo "Erro ao executar iostat"
  else
    echo ""
    echo "iostat não disponível (instale sysstat)"
  fi
  
  return 0
}

section_06_load() {
  if ! should_run_section 6; then return; fi
  
  step "[6] Load"
  section_header "6" "LOAD AVERAGE"
  
  uptime
  
  echo ""
  echo "Processos em execução vs total:"
  ps aux | wc -l || echo "Erro ao contar processos"
  
  return 0
}

section_07_network() {
  if ! should_run_section 7; then return; fi
  
  step "[7] Rede"
  section_header "7" "REDE"
  
  echo "Resumo de sockets:"
  ss -s || echo "Erro ao executar ss"
  
  echo ""
  echo "Endereços IP:"
  ip addr show || echo "Erro ao executar ip addr"
  
  echo ""
  echo "Rotas:"
  ip route || echo "Erro ao executar ip route"
  
  if command -v sar &>/dev/null; then
    echo ""
    echo "Estatísticas TCP (3 amostras):"
    sar -n TCP,ETCP 1 3 2>/dev/null || echo "Dados sar não disponíveis"
  fi
  
  echo ""
  echo "[7A] TOP 10 IPs CONECTADOS"
  ss -tn 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 || echo "Nenhuma conexão encontrada"
  
  return 0
}

section_08_apache() {
  if ! should_run_section 8; then return; fi
  
  step "[8] Apache"
  section_header "8" "APACHE"
  
  if command -v httpd &>/dev/null; then
    echo "Versão e MPM:"
    httpd -V 2>/dev/null | grep -i "version\|mpm"
    
    echo ""
    echo "Módulos relevantes:"
    apachectl -M 2>/dev/null | grep -E "mpm|rewrite|expires|headers|security" || echo "Erro ao listar módulos"
    
    echo ""
    echo "MaxRequestWorkers configurado:"
    grep -Rh "MaxRequestWorkers" /etc/apache2 /etc/httpd 2>/dev/null | grep -v "^#" || echo "Não encontrado"
    
    echo ""
    echo "Top 10 processos Apache:"
    ps -eo pid,user,%cpu,%mem,cmd | grep -E "httpd|apache2" | grep -v grep | head -10 || echo "Nenhum processo encontrado"
  else
    echo "Apache não encontrado"
  fi
  
  return 0
}

section_09_phpfpm() {
  if ! should_run_section 9; then return; fi
  
  step "[9] PHP-FPM"
  section_header "9" "PHP-FPM – POOLS E CONSUMO"
  
  if [[ -d /opt/cpanel/ea-php* ]]; then
    echo "Total de pools configurados:"
    find /opt/cpanel/ea-php*/root/etc/php-fpm.d -name "*.conf" 2>/dev/null | wc -l
    
    echo ""
    echo "Versões PHP instaladas:"
    ls -d /opt/cpanel/ea-php* 2>/dev/null | sed 's#.*/##' | sort -V
    
    echo ""
    echo "Pools e limites (pm.max_children):"
    grep -Rh "pm.max_children" /opt/cpanel/ea-php*/root/etc/php-fpm.d 2>/dev/null | sort | uniq -c | head -20
    
    echo ""
    echo "Top 10 processos PHP-FPM por CPU:"
    ps -eo user,%cpu,%mem,cmd | grep php-fpm | grep -v root | sort -k2 -rn | head -10 || echo "Nenhum processo encontrado"
  else
    echo "PHP-FPM (EA) não encontrado"
  fi
  
  return 0
}

section_10_mysql() {
  if ! should_run_section 10; then return; fi
  
  step "[10] MySQL / MariaDB"
  section_header "10" "MYSQL / MARIADB"
  
  if command -v mysqladmin &>/dev/null; then
    echo "Status do MySQL:"
    mysqladmin status 2>/dev/null || echo "Erro ao conectar no MySQL"
    
    echo ""
    echo "Threads em execução:"
    mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_running';" 2>/dev/null || echo "Erro na query"
    
    echo ""
    echo "Queries lentas:"
    mysql -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null || echo "Erro na query"
    
    echo ""
    echo "InnoDB Buffer Pool:"
    mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null || echo "Erro na query"
    
    echo ""
    echo "Max Connections:"
    mysql -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null || echo "Erro na query"
    
    echo ""
    echo "Processos MySQL/MariaDB:"
    ps -eo pid,%cpu,%mem,cmd | grep -E "mysqld|mariadbd" | grep -v grep || echo "Nenhum processo encontrado"
  else
    echo "MySQL/MariaDB não encontrado"
  fi
  
  return 0
}

section_11_top_processes() {
  if ! should_run_section 11; then return; fi
  
  step "[11] Top processos"
  section_header "11" "TOP PROCESSOS GERAIS"
  
  echo "Top 15 processos por CPU:"
  ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -16 || echo "Erro ao listar processos"
  
  echo ""
  echo "Top 15 processos por Memória:"
  ps -eo pid,user,%cpu,%mem,cmd --sort=-%mem | head -16 || echo "Erro ao listar processos"
  
  return 0
}

section_12_services() {
  if ! should_run_section 12; then return; fi
  
  step "[12] Serviços"
  section_header "12" "SERVIÇOS PRINCIPAIS"
  
  echo "Serviços em execução (principais):"
  systemctl --type=service --state=running 2>/dev/null | grep -E "httpd|php-fpm|mariadb|mysqld|exim|redis|memcached|lsws" || echo "Nenhum serviço principal encontrado"
  
  echo ""
  echo "[12A] SERVIÇOS FALHOS"
  systemctl --failed 2>/dev/null || echo "systemctl não disponível"
  
  return 0
}

section_13_kernel() {
  if ! should_run_section 13; then return; fi
  
  step "[13] Kernel / sysctl"
  section_header "13" "KERNEL / SYSCTL RELEVANTE"
  
  echo "Parâmetros sysctl importantes:"
  sysctl vm.swappiness 2>/dev/null || echo "vm.swappiness: N/A"
  sysctl fs.file-max 2>/dev/null || echo "fs.file-max: N/A"
  sysctl net.core.somaxconn 2>/dev/null || echo "net.core.somaxconn: N/A"
  sysctl net.ipv4.tcp_fin_timeout 2>/dev/null || echo "net.ipv4.tcp_fin_timeout: N/A"
  sysctl net.ipv4.tcp_tw_reuse 2>/dev/null || echo "net.ipv4.tcp_tw_reuse: N/A"
  sysctl net.ipv4.ip_local_port_range 2>/dev/null || echo "net.ipv4.ip_local_port_range: N/A"
  
  return 0
}

section_14_cloudlinux() {
  if ! should_run_section 14; then return; fi
  
  step "[14] CloudLinux / LVE"
  section_header "14" "CLOUDLINUX / LVE"
  
  if command -v lvectl &>/dev/null; then
    echo "CloudLinux detectado"
    
    echo ""
    echo "Limites LVE padrão:"
    lvectl list default 2>/dev/null || echo "Erro ao listar limites"
    
    echo ""
    echo "Top 10 usuários por uso de recursos (últimos 5 minutos):"
    lveinfo --period=5m --by-usage=cpu --display-username 2>/dev/null | head -15 || echo "lveinfo não disponível"
  else
    echo "CloudLinux não detectado"
  fi
  
  return 0
}

section_15_imunify() {
  if ! should_run_section 15; then return; fi
  
  step "[15] Imunify360"
  section_header "15" "IMUNIFY360"
  
  if command -v imunify360-agent &>/dev/null; then
    echo "Imunify360 detectado"
    
    echo ""
    echo "Versão:"
    imunify360-agent version 2>/dev/null || echo "Erro ao obter versão"
    
    echo ""
    echo "Status do serviço:"
    systemctl status imunify360 2>/dev/null | head -10 || echo "Serviço não encontrado"
  else
    echo "Imunify360 não instalado"
  fi
  
  return 0
}

# Remove apenas linhas que são comentário (# ou ; no início da linha).
# Preserva seções [ini], chaves=valor e linhas vazias.
strip_config_comments() {
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*;/d' "$1" 2>/dev/null || true
}

# ============================================================
# FUNÇÃO PRINCIPAL
# ============================================================

main() {
  parse_args "$@"
  init
  
  echo "============================================================"
  echo "RELATÓRIO DE SAÚDE – SERVIDOR CPANEL (SHARED)"
  echo "Gerado em: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Hostname: $(hostname)"
  echo "============================================================"
  
  # Executa seções
  section_01_system_identification
  section_02_cpanel_accounts
  section_03_cpu
  section_04_memory
  section_05_disk
  section_06_load
  section_07_network
  section_08_apache
  section_09_phpfpm
  section_10_mysql
  section_11_top_processes
  section_12_services
  section_13_kernel
  section_14_cloudlinux
  section_15_imunify
  
  
  # Finalização
  echo ""
  echo "============================================================"
  echo "FIM DO RELATÓRIO"
  echo "============================================================"
  echo "Arquivo gerado em: $REPORT"
  
  step "Relatório concluído"
  echo "Relatório salvo em: $REPORT" >&3
  
  # Upload opcional
  if [[ $SKIP_UPLOAD -eq 0 ]]; then
    step "Enviando para tmptext.com..."
    
    if command -v curl &>/dev/null; then
      echo "" >&3
      echo "AVISO: Enviando relatório para tmptext.com (pode conter dados sensíveis)" >&3
      echo "Para pular o upload, use: $0 --skip-upload" >&3
      echo "" >&3
      
      RESULT=$(cat "$REPORT" | bash <(curl -s "https://tmptext.com/cli.sh") 2>&1) || {
        echo "Erro ao enviar para tmptext.com" >&3
        echo "Relatório disponível localmente em: $REPORT" >&3
        exit 0
      }
      
      echo "$RESULT" >&3
    else
      echo "curl não disponível - pulando upload" >&3
    fi
  else
    echo "Upload pulado (--skip-upload)" >&3
  fi
  
  echo "" >&3
  echo "Concluído!" >&3
}

# ============================================================
# EXECUÇÃO
# ============================================================

main "$@"