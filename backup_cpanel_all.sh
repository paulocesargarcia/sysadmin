#!/bin/bash

# Script para backup completo de todos os usuários do cPanel

# Configurações
BACKUP_DIR="/backup/databases"
LOG_FILE="/backup/databases/cpanel_backup.log"
SERVER_NAME=$(hostname)
ADMIN_EMAIL="root"
DATE_FULL=$(date +"%Y%m%d_%H%M%S")
DATE_READABLE=$(date +"%d/%m/%Y às %H:%M:%S")

# Função para logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Função para enviar email
send_notification() {
    local subject="$1"
    local body="$2"
    
    if command -v mail &> /dev/null; then
        echo "$body" | mail -s "$subject" "$ADMIN_EMAIL"
    elif command -v sendmail &> /dev/null; then
        {
            echo "To: $ADMIN_EMAIL"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "$body"
        } | sendmail "$ADMIN_EMAIL"
    else
        log_message "ERRO: Nenhum comando de email encontrado (mail ou sendmail)"
    fi
}

log_message "=== INÍCIO DO BACKUP COMPLETO DO CPANEL ==="
log_message "Servidor: $SERVER_NAME"
log_message "Data/Hora: $DATE_READABLE"

mkdir -p "$BACKUP_DIR"

USERS_LIST=$(ls /var/cpanel/users | sort)
TOTAL_USERS=$(echo "$USERS_LIST" | wc -l)
SUCCESSFUL_BACKUPS=0
FAILED_BACKUPS=0
FAILED_USERS=""

log_message "Total de usuários encontrados: $TOTAL_USERS"

for USER in $USERS_LIST; do
    log_message "Iniciando backup do usuário: $USER"
    
    if /usr/local/cpanel/scripts/pkgacct --skiphomedir --backup "$USER" "$BACKUP_DIR"; then
        log_message "Backup do usuário $USER concluído com sucesso"
        SUCCESSFUL_BACKUPS=$((SUCCESSFUL_BACKUPS + 1))
    else
        log_message "ERRO: Falha no backup do usuário $USER"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
        FAILED_USERS="$FAILED_USERS\n- $USER"
    fi
done

END_TIME=$(date +"%d/%m/%Y às %H:%M:%S")
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

SUBJECT_FINAL="[BACKUP CONCLUÍDO] Servidor $SERVER_NAME - $DATE_FULL"
BODY_FINAL="Backup dos usuários do cPanel foi concluído.

=== INFORMAÇÕES DO SERVIDOR ===
Servidor: $SERVER_NAME
Data/Hora de início: $DATE_READABLE
Data/Hora de conclusão: $END_TIME

=== ESTATÍSTICAS DO BACKUP ===
Total de usuários: $TOTAL_USERS
Backups bem-sucedidos: $SUCCESSFUL_BACKUPS
Backups com falha: $FAILED_BACKUPS
Tamanho total do backup: $BACKUP_SIZE
Diretório de backup: $BACKUP_DIR

=== DETALHES ===
Opções utilizadas: --skiphomedir --backup (sem diretório home para economizar espaço)"

if [ $FAILED_BACKUPS -gt 0 ]; then
    BODY_FINAL="$BODY_FINAL

=== USUÁRIOS COM FALHA NO BACKUP ===
$FAILED_USERS

Verifique os logs em: $LOG_FILE"
fi

BODY_FINAL="$BODY_FINAL

Este backup foi executado automaticamente.
Data completa para referência: $DATE_FULL"

send_notification "$SUBJECT_FINAL" "$BODY_FINAL"

log_message "=== BACKUP CONCLUÍDO ==="
log_message "Usuários com sucesso: $SUCCESSFUL_BACKUPS"
log_message "Usuários com falha: $FAILED_BACKUPS"
log_message "Tamanho total: $BACKUP_SIZE"
log_message "Script finalizado com sucesso"

if [ $FAILED_BACKUPS -eq 0 ]; then
    exit 0
else
    exit 1
fi 

# wget 
# mkdir -p /root/scripts
# chmod +x /root/scripts/backup_cpanel_all.sh
# 00 01 * * * /root/scripts/backup_cpanel_all.sh > /dev/null 2>&1


