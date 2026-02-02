#!/bin/bash

# Script para probar conexión FTP remota
# Uso: ./ftp_test.sh <host> <user> <password> [puerto]

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

usage() {
    echo "Uso: $0 <host> <user> <password> [puerto]"
    echo ""
    echo "Parámetros:"
    echo "  host     - Dirección del servidor FTP (ej: ftp.ejemplo.com o 192.168.1.1)"
    echo "  user     - Nombre de usuario FTP"
    echo "  password - Clave del usuario"
    echo "  puerto   - (opcional) Puerto FTP, por defecto: 21"
    echo ""
    echo "Ejemplo: $0 ftp.ejemplo.com miusuario miclave"
    exit 1
}

# Validación de los parámetros
if [ $# -lt 3 ]; then
    echo -e "${RED}Error: parámetros insuficientes${NC}"
    usage
fi

HOST="$1"
USER="$2"
PASSWORD="$3"
PORT="${4:-21}"

echo "Probando conexión FTP..."
echo "  Host: $HOST"
echo "  Usuario: $USER"
echo "  Puerto: $PORT"
echo ""

# Prueba la conexión con curl
if curl -s --connect-timeout 10 \
    -u "${USER}:${PASSWORD}" \
    "ftp://${HOST}:${PORT}/" -o /dev/null 2>/dev/null; then
    echo -e "${GREEN}✓ ¡Conexión FTP exitosa!${NC}"
    exit 0
fi

# Si llegó acá, falló
echo -e "${RED}✗ Falla en la conexión FTP${NC}"
echo ""
echo "Detalles del error (curl):"
curl -v --connect-timeout 10 \
    -u "${USER}:${PASSWORD}" \
    "ftp://${HOST}:${PORT}/" -o /dev/null 2>&1 | tail -20
echo ""
echo "Posibles causas:"
echo "  - Host o puerto incorrectos"
echo "  - Usuario o clave inválidos"
echo "  - Firewall bloqueando el puerto $PORT"
echo "  - Servidor FTP inaccesible"
echo ""
echo "Prueba manual: curl -v -u $USER:*** ftp://${HOST}:${PORT}/"
exit 1
