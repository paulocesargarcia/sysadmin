#!/bin/bash

# Template do 10-opcache.ini
OPC_CONFIG="zend_extension=opcache.so
[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=512
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=65536
opcache.revalidate_freq=300
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.max_wasted_percentage=10
opcache.validate_timestamps=1
opcache.validate_permission=1
opcache.validate_root=1"

PHP_VERSIONS=$(rpm -qa --queryformat '%{NAME}\n' | grep -E "ea-php[0-9]{2}-php-cli" | sed 's/-php-cli//')

case "$1" in
    --install)
        echo "Iniciando Instalação e Configuração..."
        for VER in $PHP_VERSIONS; do
            echo "-> Configurando $VER"
            dnf install -y ${VER}-php-opcache >/dev/null 2>&1
            INI_PATH="/opt/cpanel/${VER}/root/etc/php.d/10-opcache.ini"
            echo "$OPC_CONFIG" > "$INI_PATH"
            chmod 644 "$INI_PATH"
        done
        echo "Reiniciando serviços..."
        pkill -9 php-fpm >/dev/null 2>&1
        /scripts/restartsrv_httpd --quiet
        /scripts/restartsrv_apache_php_fpm --quiet
        [ -x /usr/sbin/cagefsctl ] && cagefsctl --force-update >/dev/null 2>&1
        echo "Concluído."
        ;;

    --test)
        echo -e "\n1. Arquivos de Configuração Encontrados (Possíveis Conflitos):"
        echo "------------------------------------------------------------"
        find /opt/cpanel/ea-php*/root/etc/php.d/ -name "*opcache.ini"
        
        echo -e "\n2. Status de Execução PHP:"
        echo "------------------------------------------------------------"
        printf "%-15s | %-12s | %-10s | %-10s\n" "Versão PHP" "Status" "Mem. Usada" "Arquivos"
        echo "------------------------------------------------------------"
        for phpbin in /usr/local/bin/ea-php[0-9][0-9]; do
            if [ -f "$phpbin" ]; then
                NAME=$(basename $phpbin)
                DATA=$($phpbin -d opcache.enable_cli=1 -r "
                    \$s = opcache_get_status(false);
                    if(\$s && \$s['opcache_enabled']) {
                        echo 'OK|' . round(\$s['memory_usage']['used_memory']/1024/1024,1) . 'MB|' . \$s['opcache_statistics']['num_cached_keys'];
                    } else { echo 'OFF|---|---'; }
                " 2>/dev/null)
                
                STATUS=$(echo $DATA | cut -d'|' -f1)
                MEM=$(echo $DATA | cut -d'|' -f2)
                KEYS=$(echo $DATA | cut -d'|' -f3)

                if [ "$STATUS" == "OK" ]; then
                    printf "%-15s | \e[32m%-12s\e[0m | %-10s | %-10s\n" "$NAME" "ATIVO" "$MEM" "$KEYS"
                else
                    printf "%-15s | \e[31m%-12s\e[0m | %-10s | %-10s\n" "$NAME" "INATIVO" "---" "---"
                fi
            fi
        done
        ;;
    *)
        echo "Uso: $0 {--install|--test}"
        exit 1
        ;;
esac

# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/opcache.sh") --test