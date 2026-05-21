#!/bin/bash
#
# Provisionamento e otimização AlmaLinux 9 + cPanel
# Baseado em manuais/geracao-script.md
#
# Uso:
#   ./cpanel-config.sh --hostname vps3023.exemplo.com
#   ./cpanel-config.sh --hostname vps3023.exemplo.com --ssh-port 22022
#   ./cpanel-config.sh --hostname vps3023.exemplo.com --no-firewall --no-imunify
#

set -Eeuo pipefail

########################################
# Configuração padrão
########################################

SSH_PORT="22022"
ENABLE_FIREWALL=true
INSTALL_IMUNIFY=true
DISABLE_PASSWORD_AUTH=false
PERSIST_THP=true
RUN_CPANEL_MAINTENANCE=true

HOSTNAME_FQDN=""
HOSTNAME_SHORT=""
MAIN_IP=""

########################################
# Utilitários
########################################

log() {
    echo "[+] $*"
}

warn() {
    echo "[!] $*" >&2
}

die() {
    echo "[ERRO] $*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "Execute como root."
    fi
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: ${cmd}"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp -av "$file" "${file}.bak.$(date +%F-%H%M%S)"
    fi
}

is_valid_fqdn() {
    local host="$1"
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

set_sshd_directive() {
    local key="$1"
    local value="$2"
    local file="/etc/ssh/sshd_config"

    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]" "$file"; then
        sed -i -E "s/^[[:space:]]*#?[[:space:]]*${key}[[:space:]].*/${key} ${value}/" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

set_conf_directive() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -qE "^${key}[[:space:]]" "$file"; then
        sed -i -E "s/^${key}[[:space:]].*/${key} ${value}/" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

derive_hostname_plus_one() {
    local fqdn="$1"
    local first_label="${fqdn%%.*}"
    local rest="${fqdn#*.}"

    if [[ "$first_label" =~ ([0-9]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local prefix="${first_label:0:${#first_label}-${#num}}"

        [[ -n "$prefix" ]] || return 1

        local width=${#num}
        local new_num=$((10#$num + 1))
        printf -v padded "%0*d" "$width" "$new_num"
        echo "${prefix}${padded}.${rest}"
        return 0
    fi

    return 1
}

append_limits_if_missing() {
    local file="/etc/security/limits.conf"
    local marker="# cpanel-config.sh - nofile limits"

    if grep -qF "$marker" "$file" 2>/dev/null; then
        log "limits.conf já configurado, pulando."
        return 0
    fi

    cat >> "$file" <<EOF

${marker}
* soft nofile 65535
* hard nofile 65535
EOF
}

usage() {
    cat <<EOF
Uso: $(basename "$0") --hostname FQDN [opções]

Opções obrigatórias:
  --hostname FQDN          Hostname completo (ex: vps3023.exemplo.com)

Opções:
  --ssh-port PORTA         Porta SSH (padrão: 22022)
  --no-firewall            Não configurar firewalld
  --no-imunify             Não instalar ImunifyAV
  --disable-password-auth  Define PasswordAuthentication no no SSH
  --no-thp-persist         Não criar unidade systemd para THP
  --skip-cpanel            Pula manutenção cPanel (check_cpanel_pkgs/upcp)
  -h, --help               Exibe esta ajuda

Exemplo:
  $(basename "$0") --hostname vps3023.exemplo.com
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        die "Parâmetro --hostname é obrigatório."
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname)
                [[ $# -ge 2 ]] || die "Valor ausente para --hostname."
                HOSTNAME_FQDN="$2"
                shift 2
                ;;
            --ssh-port)
                [[ $# -ge 2 ]] || die "Valor ausente para --ssh-port."
                SSH_PORT="$2"
                shift 2
                ;;
            --no-firewall)
                ENABLE_FIREWALL=false
                shift
                ;;
            --no-imunify)
                INSTALL_IMUNIFY=false
                shift
                ;;
            --disable-password-auth)
                DISABLE_PASSWORD_AUTH=true
                shift
                ;;
            --no-thp-persist)
                PERSIST_THP=false
                shift
                ;;
            --skip-cpanel)
                RUN_CPANEL_MAINTENANCE=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Opção desconhecida: $1"
                ;;
        esac
    done

    [[ -n "$HOSTNAME_FQDN" ]] || die "Parâmetro --hostname é obrigatório."
    is_valid_fqdn "$HOSTNAME_FQDN" || die "Hostname inválido (esperado FQDN): ${HOSTNAME_FQDN}"

    HOSTNAME_SHORT="${HOSTNAME_FQDN%%.*}"
    MAIN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "$MAIN_IP" ]] || die "Não foi possível detectar o IP principal (hostname -I)."
}

preflight() {
    require_root
    require_cmd hostnamectl
    require_cmd dnf
    require_cmd systemctl

    if [[ "$ENABLE_FIREWALL" == true ]]; then
        require_cmd firewall-cmd
        require_cmd semanage
    fi
}

########################################
# Etapas de provisionamento
########################################

configure_hostname() {
    log "Configurando hostname: ${HOSTNAME_FQDN}"

    hostnamectl set-hostname "${HOSTNAME_FQDN}"

    if [[ -x /usr/local/cpanel/bin/set_hostname ]]; then
        /usr/local/cpanel/bin/set_hostname "${HOSTNAME_FQDN}"
    else
        warn "cPanel não detectado; pulando set_hostname."
    fi
}

configure_hosts() {
    log "Atualizando /etc/hosts"

    backup_file /etc/hosts

    cat > /etc/hosts <<EOF
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain

${MAIN_IP} ${HOSTNAME_FQDN} ${HOSTNAME_SHORT}
EOF

    getent hosts "${HOSTNAME_FQDN}" >/dev/null || warn "getent hosts falhou para ${HOSTNAME_FQDN}"
}

update_system() {
    log "Atualizando sistema"

    dnf -y update
    dnf -y autoremove || true
}

install_packages() {
    log "Instalando pacotes"

    dnf -y install \
        htop \
        screen \
        vim \
        net-snmp \
        net-snmp-utils \
        policycoreutils-python-utils \
        lsof \
        wget \
        curl \
        zip \
        unzip \
        tar \
        rsync \
        bind-utils \
        sysstat \
        iotop \
        nload \
        iftop \
        chrony \
        cronie \
        bc \
        jq
}

configure_chrony() {
    log "Configurando chronyd"

    systemctl enable chronyd
    systemctl restart chronyd

    if command -v chronyc >/dev/null 2>&1; then
        chronyc tracking || warn "chronyc tracking retornou erro."
    fi
}

configure_firewall() {
    if [[ "$ENABLE_FIREWALL" != true ]]; then
        log "Firewall desabilitado via parâmetro, pulando."
        return 0
    fi

    log "Configurando firewalld (porta SSH ${SSH_PORT})"

    systemctl enable firewalld
    systemctl start firewalld

    semanage port -a -t ssh_port_t -p tcp "${SSH_PORT}" 2>/dev/null || true

    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp" || true
    firewall-cmd --reload
}

configure_ssh() {
    log "Hardening SSH (porta ${SSH_PORT})"

    backup_file /etc/ssh/sshd_config

    set_sshd_directive "Port" "${SSH_PORT}"
    set_sshd_directive "UseDNS" "no"
    set_sshd_directive "MaxAuthTries" "3"
    set_sshd_directive "ClientAliveInterval" "300"
    set_sshd_directive "ClientAliveCountMax" "2"

    if [[ "$DISABLE_PASSWORD_AUTH" == true ]]; then
        set_sshd_directive "PasswordAuthentication" "no"
        warn "PasswordAuthentication desabilitado. Confirme acesso por chave SSH antes de desconectar."
    fi

    # PermitRootLogin não é alterado automaticamente (política do servidor)

    sshd -t
    systemctl restart sshd
}

optimize_apache() {
    local includes_dir="/etc/apache2/conf.d/includes"
    local include_file="${includes_dir}/pre_virtualhost_global.conf"
    local marker_start="# BEGIN cpanel-config.sh - apache keepalive"
    local marker_end="# END cpanel-config.sh - apache keepalive"

    if [[ ! -d "$includes_dir" ]]; then
        warn "Diretório ${includes_dir} não encontrado; pulando otimização Apache."
        return 0
    fi

    log "Otimizando Apache KeepAlive via ${include_file}"

    if [[ -f "$include_file" ]]; then
        backup_file "$include_file"

        if grep -qF "$marker_start" "$include_file"; then
            awk -v start="$marker_start" -v end="$marker_end" '
                $0 == start { skip=1; next }
                $0 == end { skip=0; next }
                !skip { print }
            ' "$include_file" > "${include_file}.tmp"
            mv "${include_file}.tmp" "$include_file"
        fi
    fi

    cat >> "$include_file" <<EOF

${marker_start}
KeepAlive On
KeepAliveTimeout 2
MaxKeepAliveRequests 100
Timeout 60

<IfModule reqtimeout_module>
    RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500
</IfModule>

${marker_end}
EOF

    if [[ -x /scripts/rebuildhttpdconf ]]; then
        /scripts/rebuildhttpdconf || warn "rebuildhttpdconf retornou erro."
    else
        warn "/scripts/rebuildhttpdconf não encontrado; httpd.conf não reconstruído."
    fi

    if command -v apachectl >/dev/null 2>&1; then
        apachectl configtest || warn "apachectl configtest retornou erro."
    fi

    if [[ -x /scripts/restartsrv_httpd ]]; then
        /scripts/restartsrv_httpd || warn "restartsrv_httpd retornou erro."
    elif systemctl is-active --quiet httpd 2>/dev/null; then
        systemctl restart httpd || warn "systemctl restart httpd retornou erro."
    else
        warn "Apache não reiniciado (serviço não ativo ou comandos indisponíveis)."
    fi
}

configure_sysctl() {
    log "Aplicando tuning sysctl"

    cat > /etc/sysctl.d/99-performance.conf <<EOF
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
fs.file-max = 2097152
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

    sysctl --system
}

configure_limits() {
    log "Ajustando limits.conf"
    append_limits_if_missing
}

disable_thp() {
    local thp_enabled="/sys/kernel/mm/transparent_hugepage/enabled"

    if [[ ! -f "$thp_enabled" ]]; then
        warn "THP não disponível neste kernel, pulando."
        return 0
    fi

    log "Desabilitando Transparent Huge Pages"

    echo never > "$thp_enabled" || warn "Falha ao desabilitar THP em runtime."

    if [[ "$PERSIST_THP" != true ]]; then
        return 0
    fi

    local unit="/etc/systemd/system/disable-thp.service"

    cat > "$unit" <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl enable disable-thp.service
    systemctl start disable-thp.service || true
}

configure_wwwacct_conf() {
    local conf="/etc/wwwacct.conf"
    local hostname_plus_one
    local contact_email="paulo@setik.com.py,setik@setik.com.py"

    if [[ ! -f "$conf" ]]; then
        warn "Arquivo ${conf} não encontrado; pulando wwwacct.conf."
        return 0
    fi

    if ! hostname_plus_one="$(derive_hostname_plus_one "$HOSTNAME_FQDN")"; then
        warn "Prefixo do hostname não termina com número (${HOSTNAME_SHORT}); pulando wwwacct.conf."
        return 0
    fi

    log "Configurando ${conf}"

    backup_file "$conf"

    set_conf_directive "$conf" "ADDR" "$MAIN_IP"
    set_conf_directive "$conf" "HOST" "$HOSTNAME_FQDN"
    set_conf_directive "$conf" "NS" "$HOSTNAME_FQDN"
    set_conf_directive "$conf" "NS2" "$hostname_plus_one"
    set_conf_directive "$conf" "CONTACTEMAIL" "$contact_email"

    if [[ -x /scripts/updateuserdomains ]]; then
        /scripts/updateuserdomains || warn "updateuserdomains retornou erro."
    else
        warn "/scripts/updateuserdomains não encontrado; cache de domínios não atualizado."
    fi

    echo
    echo "===== wwwacct.conf ====="
    grep -E "^(ADDR|HOST|NS |NS2 |CONTACTEMAIL)" "$conf"
}

configure_cpanel() {
    if [[ "$RUN_CPANEL_MAINTENANCE" != true ]]; then
        log "Manutenção cPanel desabilitada via parâmetro, pulando."
        return 0
    fi

    if [[ ! -d /usr/local/cpanel ]]; then
        warn "Diretório /usr/local/cpanel não encontrado; pulando manutenção cPanel."
        return 0
    fi

    log "Executando manutenção cPanel"

    if [[ -x /usr/local/cpanel/scripts/check_cpanel_pkgs ]]; then
        /usr/local/cpanel/scripts/check_cpanel_pkgs --fix || warn "check_cpanel_pkgs retornou erro."
    fi

    if [[ -x /usr/local/cpanel/scripts/upcp ]]; then
        /usr/local/cpanel/scripts/upcp --force || warn "upcp retornou erro."
    fi
}

install_imunify() {
    if [[ "$INSTALL_IMUNIFY" != true ]]; then
        log "Instalação ImunifyAV desabilitada via parâmetro, pulando."
        return 0
    fi

    log "Verificando ImunifyAV"

    if rpm -qa 2>/dev/null | grep -qi imunify; then
        log "Imunify já instalado, pulando."
        return 0
    fi

    require_cmd wget

    local deploy_script="/root/imav-deploy.sh"
    wget -q https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh -O "$deploy_script"
    bash "$deploy_script" || warn "Instalação ImunifyAV retornou erro."
}

configure_snmp() {
    log "Habilitando SNMP"

    systemctl enable snmpd
    systemctl restart snmpd || warn "snmpd restart retornou erro."
}

cleanup_old_kernels() {
    if command -v package-cleanup >/dev/null 2>&1; then
        log "Removendo kernels antigos (mantendo 2)"
        package-cleanup --oldkernels --count=2 -y || warn "package-cleanup retornou erro."
    fi
}

print_status() {
    echo
    echo "========================================="
    echo " Provisionamento concluído"
    echo "========================================="
    echo
    hostnamectl
    echo
    free -m
    echo
    uptime
    echo
    df -h /
    echo
    ss -tunlp 2>/dev/null | grep -E ":${SSH_PORT}[[:space:]]" || warn "Porta SSH ${SSH_PORT} não encontrada em ss -tunlp."
    echo
    systemctl --failed 2>/dev/null || true
}

main() {
    parse_args "$@"
    preflight

    clear || true

    echo "========================================="
    echo " Provisionamento AlmaLinux 9 + cPanel"
    echo " Hostname: ${HOSTNAME_FQDN}"
    echo " IP:       ${MAIN_IP}"
    echo " SSH:      ${SSH_PORT}"
    echo "========================================="
    echo

    configure_hostname
    configure_hosts
    configure_wwwacct_conf
    update_system
    install_packages
    configure_chrony
    configure_firewall
    configure_ssh
    optimize_apache
    configure_sysctl
    configure_limits
    disable_thp
    configure_cpanel
    install_imunify
    configure_snmp
    cleanup_old_kernels
    print_status
}

main "$@"


# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-config.sh") --hostname vps3023.exemplo.com