#!/bin/bash

DESTINO=$(pwd)

if [ -z "$1" ]; then
    echo "Uso: $0 all | usuario1,usuario2,usuario3"
    exit 1
fi

if [ "$1" == "all" ]; then
    USERS=$(ls -A /var/cpanel/users)
else
    IFS=',' read -ra USERS <<< "$1"
fi

for user in "${USERS[@]}"; do
    echo "Iniciando backup da conta: $user"
    /scripts/pkgacct "$user" "$DESTINO"
done

echo "Backups finalizados em: $DESTINO"

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/backup_cpanel.sh")

