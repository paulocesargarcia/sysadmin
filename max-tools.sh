#!/bin/bash

GITHUB_REPO_URL="https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/max-tools.sh"

show_help() {
    echo "max-tools - Ferramenta para analise do servidor."
    echo "Uso: $0 [opções]"
    echo "  --help                   Exibe ajuda da ferramenta"
    echo "  --top                    Exibe o uso recursos do servidor"
    echo "  --ip_abuse [ip]          Exibe os usuários com uso excessivo para de um IP"
    echo "  --ip_block [ip]          Bloquear o IP especificado"
    echo "  --list_blocked           Lista todas as regras de bloqueio no firewall"
    echo "  --install                Instalar a versão mais recente"
}

tool_check_deps() {
    local dependencies=("$@")
    for dep in "${dependencies[@]}"; do
        command -v $dep &> /dev/null || { echo "Falta: $dep"; exit 1; }
    done
}

tool_top_command() {
    tool_check_deps "mysqladmin" "ps"
    mysqladmin processlist
    ps -eo user,pid,%cpu,%mem,comm --sort=-%cpu,-%mem | head
}

tool_ip_abuse() {
    tool_check_deps "ss" "awk" "sed" "xargs"
    local ip="$1"
    ss -tp | grep "$ip" | awk '{print $6}' | sed 's/.*pid=\([0-9]*\),.*/\1/' | xargs -r -I{} ps -p {} -o user=
}

tool_ip_block() {
    tool_check_deps "firewall-cmd"
    firewall-cmd --add-rich-rule="rule family='ipv4' source address='$1' reject"
}

tool_list_blocked() {
    tool_check_deps "firewall-cmd"
    firewall-cmd --list-all
}

tool_install() {
    tool_check_deps "curl" "mkdir"
    INSTALL_DIR="/root/bin"
    SCRIPT_NAME="max-tools"

    [ ! -d "$INSTALL_DIR" ] && mkdir -p "$INSTALL_DIR"
    curl -s -H 'Cache-Control: no-cache' -o "$INSTALL_DIR/$SCRIPT_NAME.sh" "$GITHUB_REPO_URL"
    mv -f "$INSTALL_DIR/$SCRIPT_NAME.sh" "$INSTALL_DIR/$SCRIPT_NAME"
    chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"
    chown root:root "$INSTALL_DIR/$SCRIPT_NAME"

    echo "Instalacao completa. O script esta disponivel em $INSTALL_DIR/$SCRIPT_NAME."
}

# Exibe o help se nenhum parâmetro for passado
[ $# -eq 0 ] && show_help && exit 0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) show_help; exit 0 ;;
        --top) tool_top_command; shift ;;
        --ip_abuse) [ -z "$2" ] && echo "IP necessário." && exit 1; tool_ip_abuse "$2"; shift 2 ;;
        --ip_block) [ -z "$2" ] && echo "IP necessário." && exit 1; tool_ip_block "$2"; shift 2 ;;
        --list_blocked_ips) tool_list_blocked_ips "$2"; shift 2 ;;
        --install) tool_install; shift ;;
        *) echo "Opção inválida: $1"; show_help; exit 1 ;;
    esac
done
