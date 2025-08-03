#!/bin/bash

DATA=$(date +%F)
BACKUP_DIR="/backup/mysql_$DATA"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Início do backup em $(date)"

DBS=$(mysql -u root -e "SHOW DATABASES;" | grep -Ev "Database|information_schema|performance_schema|mysql|sys")

for DB in $DBS; do
  echo "Backup do banco: $DB"

  mysqldump \
    --no-data \
    --routines \
    --triggers \
    --events \
    --single-transaction \
    --skip-lock-tables \
    --default-character-set=utf8mb4 \
    --set-gtid-purged=OFF \
    --add-drop-table \
    -u root "$DB" | gzip > "$BACKUP_DIR/${DB}_structure.sql.gz"

  if [[ $? -ne 0 ]]; then
    echo "[ERRO] Falha ao exportar estrutura de $DB" >&2
    continue
  fi

  mysqldump \
    --no-create-info \
    --single-transaction \
    --skip-lock-tables \
    --default-character-set=utf8mb4 \
    --set-gtid-purged=OFF \
    -u root "$DB" | gzip > "$BACKUP_DIR/${DB}_data.sql.gz"

  if [[ $? -ne 0 ]]; then
    echo "[ERRO] Falha ao exportar dados de $DB" >&2
    continue
  fi

  echo "[OK] Backup de $DB concluído"
done

echo "Backup finalizado em $(date)"

# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/backup_databases_all.sh")