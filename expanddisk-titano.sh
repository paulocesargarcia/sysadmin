#!/bin/bash

# ====================================================================
# expanddisk-titano
# Auto-expansión segura de la partición raíz (/) bajo LVM
# Diseñado por: TERRAFORM LARA
# LATENT AUTONOMOUS RESOURCE ARCHITECTURE - 2025
# ====================================================================

set -e

echo "------------------------------------------------------------"
echo " INICIO - EXPANSIÓN DE PARTICIÓN / (LVM)"
echo " Diseñado por: TERRAFORM LARA - LATENT AUTONOMOUS RESOURCE"
echo " Fecha: $(date)"
echo "------------------------------------------------------------"

# Paso 1: Detectar sistema operativo
OS=$(grep -oP '(?<=^ID=).*' /etc/os-release | tr -d '"')

echo "[1/5] Detectando sistema operativo..."
echo "Sistema detectado: $OS"

# Paso 2: Instalar dependencias (sin epel-release en CloudLinux)
echo "[2/5] Instalando paquetes requeridos..."
if [[ "$OS" != "cloudlinux" ]]; then
    dnf install -y epel-release > /dev/null || echo "⚠️  epel-release no se pudo instalar, continuando..."
fi

dnf install -y lvm2 xfsprogs cloud-utils-growpart parted > /dev/null

# Variables
DISK="/dev/vda"
PARTITION="${DISK}2"
PV=$PARTITION
VG=$(vgs --noheadings -o vg_name | awk '{print $1}')
LV=$(lvs --noheadings -o lv_name | grep root | awk '{print $1}')
LV_PATH="/dev/${VG}/${LV}"

# Estado antes
echo "[3/5] Estado del sistema ANTES de la expansión:"
df -h | grep "$LV_PATH" || true
lsblk | grep -E 'sda|almalinux' || true

# Expandir partición
echo "[4/5] Expandiendo partición ${PARTITION}..."
growpart $DISK 2 || true

# Redimensionar volumen físico
echo "[5/5] Redimensionando volumen físico (${PV})..."
pvresize $PV

# Extender volumen lógico y filesystem
echo "[6/6] Expandiendo volumen lógico ${LV_PATH} y sistema de archivos..."
lvextend -l +100%FREE "$LV_PATH" -r

# Estado después
echo ""
echo "------------------------------------------------------------"
echo " FINALIZADO - ESTADO DESPUÉS DE LA EXPANSIÓN"
echo "------------------------------------------------------------"
df -h | grep "$LV_PATH" || true
lsblk | grep -E 'sda|almalinux' || true

echo ""
echo "✅ La partición raíz (/) ha sido expandida exitosamente."
echo "✅ Script ejecutado correctamente por TERRAFORM LARA."
echo "------------------------------------------------------------"

# Como usar remote:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/expanddisk-titano.sh")
