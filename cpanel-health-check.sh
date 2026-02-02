#!/bin/bash

# ===============================================================
# NOMBRE: cpanel-health-check.sh
# DESCRIPCIÓN: Diagnóstico Especialista de Performance e Integridad
# LOG: Genera salida en pantalla y en un archivo .log
# ===============================================================

# Definición del archivo de log
LOG_FILE="health_check_$(hostname)_$(date +%Y%m%d_%H%M%S).log"

# Función para enviar salida a pantalla y archivo simultáneamente
exec > >(tee -i "$LOG_FILE") 2>&1

clear
echo "==============================================================="
echo "       REPORTE TÉCNICO DE SALUD DEL SERVIDOR (SISTEMAS)"
echo "==============================================================="

# --- 1. IDENTIFICACIÓN DEL SISTEMA ---
echo -e "\n[1. IDENTIFICACIÓN DEL EQUIPO]"
echo "Hostname:          $(hostname)"
echo "Fecha del Análisis: $(date '+%d/%m/%Y %H:%M:%S')"
echo "Tiempo prendido:   $(uptime -p)"
echo "Versión del SO:    $(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel:            $(uname -r)"
echo "Versión de cPanel: $(/usr/local/cpanel/cpanel -V)"
echo "IP Principal:      $(hostname -I | awk '{print $1}')"

# --- 2. RECURSOS DE HARDWARE ---
echo -e "\n[2. RECURSOS Y CARGA DEL SISTEMA (LOAD)]"
echo "CPU (Núcleos):     $(nproc)"
echo "Carga promedio:    $(cat /proc/loadavg)"
echo -e "\n--- Memoria RAM ---"
free -h
echo -e "\n--- Almacenamiento (Particiones principales) ---"
df -h | grep -E '^Filesystem|/$|/var|/home|/usr'

# --- 3. ESTADO DE LOS SERVICIOS ---
echo -e "\n[3. ESTADO DE LOS SERVICIOS CRÍTICOS]"
for service in httpd mysql php-fpm cpanel tailwatchd; do
    printf "%-15s: " "$service"
    if pgrep -x "$service" > /dev/null || ([ "$service" == "httpd" ] && pgrep -x "httpd" > /dev/null); then
        echo "FUNCIONANDO"
    else
        echo "¡FALLÓ! / PARADO"
    fi
done

# --- 4. ANÁLISIS DE PHP-FPM ---
echo -e "\n[4. CONFIGURACIÓN Y RENDIMIENTO PHP-FPM]"
echo "Versión de PHP (CLI): $(php -v | head -n 1)"
echo "Límites de max_children configurados:"
grep -r "pm.max_children" /opt/cpanel/ea-php*/root/etc/php-fpm.d/ | awk -F: '{print $1 " -> " $2}' | sed 's/\/opt\/cpanel\///g'

# --- 5. BASE DE DATOS (MySQL/MariaDB) ---
echo -e "\n[5. ESTADÍSTICAS DE LA BASE DE DATOS]"
if mysqladmin ping &>/dev/null; then
    mysqladmin proc stat
else
    echo "¡ERROR!: No se pudo entrar al MySQL, capaz está colgado."
fi

# --- 6. RED Y CONEXIONES ---
echo -e "\n[6. CONEXIONES DE RED ACTUALES]"
echo "Puerto 80 (HTTP):   $(netstat -an | grep :80 | grep ESTABLISHED | wc -l) establecidas"
echo "Puerto 443 (HTTPS): $(netstat -an | grep :443 | grep ESTABLISHED | wc -l) establecidas"
echo -e "\n--- Los 10 IPs que más están entrando (Top Connections) ---"
netstat -antu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 10

# --- 7. ÚLTIMOS ERRORES (PHP-FPM) ---
echo -e "\n[7. ÚLTIMOS ERRORES DE PHP-FPM (Global)]"
tail -n 20 /opt/cpanel/ea-php*/root/usr/var/log/php-fpm/error.log 2>/dev/null

# --- 8. PROCESOS PESADOS ---
echo -e "\n[8. LOS 10 PROCESOS QUE MÁS COMEN CPU/MEMORIA]"
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 11

echo -e "\n==============================================================="
echo "              FIN DEL DIAGNÓSTICO - ¡LISTO EL POLLO!"
echo "El reporte se guardó en: $LOG_FILE"
echo "==============================================================="

# Instrucción para usar directo desde la nube:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-health-check.sh")