#!/bin/bash

# Script para alterar disable_functions e ajustar diretivas PHP nas versões instaladas do PHP no cPanel

# Primeira parte: alterar disable_functions no php.ini
for version in $(ls /opt/cpanel/ | grep ea-php); do
    ini_file="/opt/cpanel/$version/root/etc/php.ini"
    
    if [ -f "$ini_file" ]; then
        sed -i 's/^disable_functions.*/disable_functions = "mail,exec,passthru,shell_exec,system,proc_open,popen,show_source,pcntl_exec,eval,symlink,link,escapeshellarg,escapeshellcmd,dl,openlog,syslog,readlink,popepassthru,stream_socket_server,fsockopen,apache_child_terminate,apache_setenv,ftp_connect,ftp_exec,ftp_get,ftp_put,allow_url_fopen,allow_url_include"/' "$ini_file"
        echo "Atualizado disable_functions em $ini_file"
    else
        echo "php.ini não encontrado para $version"
    fi
done

# Segunda parte: ajustar diretivas PHP usando WHM API
# Configurar diretivas PHP para cada versão encontrada
for version in $(ls /opt/cpanel/ | grep ea-php); do
  whmapi1 php_ini_set_directives \
    directive-1='allow_url_fopen:0' \
    directive-3='display_errors:1' \
    directive-4='file_uploads:1' \
    directive-5='memory_limit:512M' \
    directive-6='post_max_size:512M' \
    directive-7='upload_max_filesize:512M' \
    directive-8='zlib.output_compression:1' \
    version="$version"
    
  echo "Diretivas PHP ajustadas para a versão $version"
done

# Reiniciar Apache e PHP-FPM após as mudanças
/scripts/restartsrv_apache_php_fpm
echo "Serviço Apache e PHP-FPM reiniciados."
