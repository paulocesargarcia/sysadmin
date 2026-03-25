#!/bin/bash
# add-client.sh - Adiciona novo cliente ao sistema de backup

if [ $# -lt 1 ]; then
    echo "Uso: $0 <hostname> [porta] [backup_path]"
    exit 1
fi

HOST=$1
PORT=${2:-22}
BACKUP_PATH=$3

# Gera backup_path automático se não informado
if [ -z "$BACKUP_PATH" ]; then
    BACKUP_PATH="/backup/${HOST}"
fi

CONFIG="/root/backup-central/config.yaml"

# Cria diretório de backup
mkdir -p "${BACKUP_PATH}/databases" "${BACKUP_PATH}/home"

# Copia chave SSH
echo "Copiando chave SSH para ${HOST} (porta ${PORT})..."
ssh-copy-id -o StrictHostKeyChecking=no -p ${PORT} root@${HOST}

# Instala script de backup se não existir
ssh -p ${PORT} root@${HOST} '
    if [ ! -f /root/backup_cpanel_all.sh ]; then
        echo "Instalando backup_cpanel_all.sh..."
        wget -q https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/backup_cpanel_all.sh -O /root/backup_cpanel_all.sh
        chmod +x /root/backup_cpanel_all.sh
    fi
'

# Adiciona ao config.yaml
if ! grep -q "hostname: ${HOST}" "$CONFIG" 2>/dev/null; then
    cat >> "$CONFIG" << EOF

  - hostname: ${HOST}
    port: ${PORT}
    backup_path: ${BACKUP_PATH}
EOF
    echo "Cliente ${HOST} adicionado com sucesso."
else
    echo "Cliente ${HOST} já existe no config."
fi

/*
    wget https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/backup/add-client.sh
    wget https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/backup/backup-orchestrator.sh
    mkdir -p /root/backup-central
    chmod +x /root/backup-central/add-client.sh /root/backup-central/backup-orchestrator.sh
*/