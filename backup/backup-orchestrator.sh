#!/bin/bash
# backup-orchestrator.sh - Executa backup de todos os clientes

CONFIG="/root/backup-central/config.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Arquivo de configuração não encontrado: $CONFIG"
    exit 1
fi

# Processa cada cliente
while IFS= read -r line; do
    if [[ $line =~ hostname:\ (.*) ]]; then
        HOST="${BASH_REMATCH[1]}"
        
        # Lê porta e backup_path (suporte a yaml simples)
        PORT=$(grep -A3 "hostname: ${HOST}" "$CONFIG" | grep "port:" | awk '{print $2}' || echo "22")
        BACKUP_PATH=$(grep -A3 "hostname: ${HOST}" "$CONFIG" | grep "backup_path:" | awk '{print $2}')
        
        if [ -z "$BACKUP_PATH" ]; then
            BACKUP_PATH="/backup/${HOST}"
        fi

        echo "=== Iniciando backup de ${HOST} ==="

        # Executa backup cPanel no cliente
        ssh -p ${PORT} root@${HOST} "/root/backup_cpanel_all.sh"

        # Rsync databases
        rsync -avz --delete -e "ssh -p ${PORT}" \
            root@${HOST}:/backup/databases/ \
            "${BACKUP_PATH}/databases/"

        # Rsync apenas usuários reais do cPanel
        USERS=$(ssh -p ${PORT} root@${HOST} "ls /var/cpanel/users/ 2>/dev/null | grep -v '^root$'")

        for user in $USERS; do
            rsync -avz --delete -e "ssh -p ${PORT}" \
                root@${HOST}:/home/${user}/ \
                "${BACKUP_PATH}/home/${user}/"
        done

        echo "Backup de ${HOST} finalizado."
        echo
    fi
done < <(grep "hostname:" "$CONFIG")