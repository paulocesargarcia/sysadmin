#!/bin/bash

DESTINO=$(pwd)
USERS=()

# Parse argumentos
for arg in "$@"; do
    case $arg in
        --all)
            mapfile -t USERS < <(ls -A /var/cpanel/users)
            ;;
        --user=*)
            IFS=',' read -ra USERS <<< "${arg#*=}"
            ;;
        *)
            echo "Uso: $0 [--all] [--user=usuario1,usuario2]"
            exit 1
            ;;
    esac
done

# Verificação
if [ ${#USERS[@]} -eq 0 ]; then
    echo "Nenhuma conta especificada para backup."
    exit 1
fi

# Execução dos backups
for user in "${USERS[@]}"; do
    echo "Iniciando backup da conta: $user"
    /scripts/pkgacct "$user" "$DESTINO"
done

echo "Backups finalizados em: $DESTINO"

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/backup_cpanel.sh")

