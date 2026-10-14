#!/bin/bash
#
# Desativa notificações específicas do cPHulk/cPanel.
#
# Uso remoto:
#   bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-disable-cphulk-notifications.sh")
#

set -Eeuo pipefail

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

require_whmapi1() {
    command -v whmapi1 >/dev/null 2>&1 || die "Comando whmapi1 não encontrado. Execute em um servidor cPanel/WHM."
}

run_whmapi1() {
    local description="$1"
    shift

    log "$description"

    if whmapi1 "$@"; then
        log "OK: $description"
    else
        warn "Falha ao aplicar: $description"
    fi

    echo
}

main() {
    require_root
    require_whmapi1

    log "Desativando notificações do cPHulk/cPanel"
    echo

    run_whmapi1 \
        "Desativando cPHulk Configuration Issues" \
        set_application_contact_event_importance \
        app='Install' \
        event='FixcPHulkConf' \
        importance='Disabled'

    run_whmapi1 \
        "Desativando cPHulk Database Integrity Notices" \
        set_application_contact_event_importance \
        app='Install' \
        event='CheckcPHulkDB' \
        importance='Disabled'

    run_whmapi1 \
        "Desativando cPHulkd Brute Force" \
        set_application_contact_event_importance \
        app='cPHulk' \
        event='BruteForce' \
        importance='Disabled'

    run_whmapi1 \
        "Desativando notificações gerais do cPHulkd" \
        set_application_contact_importance \
        app='cPHulk' \
        importance='Disabled'

    run_whmapi1 \
        "Definindo notificações de login do cPHulkd como Low" \
        set_application_contact_event_importance \
        app='cPHulk' \
        event='Login' \
        importance='Low'

    log "Concluído."
}

main "$@"
