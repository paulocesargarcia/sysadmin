#!/bin/bash

# Verifica se o script está sendo executado como root
[ "$(id -u)" -ne 0 ] && echo "Execute como root." && exit 1

# Definição da variável do link do GitHub
GITHUB_REPO_URL="https://github.com/seu_usuario/seu_repositorio.git"

# Função de ajuda
/**
 * Exibe a ajuda da ferramenta.
 * @example
 * $0 --help
 */
show_help() {
    echo "max-tools - Ferramenta para analise do servidor."
    echo "Uso: $0 [opções]"
    echo "  --help                   Exibe ajuda da ferramenta"
    echo "  --top                    Exibe o uso recursos do servidor"
    echo "  --ip_abuse [ip]          Exibe os usuários com uso excessivo para de um IP"
    echo "  --ip_block [ip]          Bloquear o IP especificado"
    echo "  --list_blocked_ips [ip]  Lista IPs bloqueados, opcionalmente filtra por [ip]"
    echo "  --update                 Atualizar o script"
}

/**
 * Lista IPs bloqueados no firewall-cmd.
 * Se um IP for fornecido, filtra o IP específico; caso contrário, lista todos os IPs bloqueados.
 * @param [ip] - (Opcional) IP a ser filtrado
 * @example
 * $0 --list_blocked_ips
 * $0 --list_blocked_ips 192.168.0.1
 */
tool_list_blocked_ips() {
    tool_check_deps "firewall-cmd"
    if [ -z "$1" ]; then
        firewall-cmd --list-all | grep "rule family='ipv4'" | grep "reject"
    else
        firewall-cmd --list-all | grep "rule family='ipv4' source address='$1' reject"
    fi
}

/**
 * Verifica se as dependências necessárias estão instaladas.
 * @param dependencies - Lista de dependências a serem verificadas
 */
tool_check_deps() {
    local dependencies=("$@")
    for dep in "${dependencies[@]}"; do
        command -v $dep &> /dev/null || { echo "Falta: $dep"; exit 1; }
    done
}

/**
 * Exibe o uso de recursos do servidor, listando processos que utilizam mais CPU e memória.
 * @example
 * $0 --top
 */
tool_top_command() {
    tool_check_deps "mysqladmin" "ps"
    mysqladmin processlist
    ps -eo user,pid,%cpu,%mem,comm --sort=-%cpu,-%mem | head
}

/**
 * Exibe os usuários com uso excessivo para de um IP específico.
 * @param ip - Endereço IP a ser verificado
 * @example
 * $0 --ip_abuse 192.168.0.1
 */
tool_ip_abuse() {
    tool_check_deps "ss" "awk" "sed" "xargs"
    local ip="$1"
    ss -tp | grep "$ip" | awk '{print $6}' | sed 's/.*pid=\([0-9]*\),.*/\1/' | xargs -r -I{} ps -p {} -o user=
}

/**
 * Bloqueia o IP especificado utilizando o firewall-cmd.
 * @param ip - Endereço IP a ser bloqueado
 * @example
 * $0 --ip_block 192.168.0.1
 */
tool_ip_block() {
    tool_check_deps "firewall-cmd"
    firewall-cmd --add-rich-rule="rule family='ipv4' source address='$1' reject"
}

/**
 * Atualiza o script para a última versão do repositório GitHub.
 * @example
 * $0 --update
 */
tool_update() {
    tool_check_deps "git"
    SCRIPT_PATH=$(realpath "$0")
    git pull "$GITHUB_REPO_URL" main && chmod 700 "$SCRIPT_PATH" && chown root:root "$SCRIPT_PATH" && echo "Atualizado." || echo "Erro na atualização."
}

[ $# -eq 0 ] && show_help && exit 0