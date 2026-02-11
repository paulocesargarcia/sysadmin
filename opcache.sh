#!/bin/bash

# Configurações para Hosting Compartilhado
OPC_TUNE="opcache.enable=1
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
        echo "Limpando e Instalando OPcache..."
        for VER in $PHP_VERSIONS; do
            echo "-> Processando $VER"
            # 1. Instala o pacote oficial
            dnf install -y ${VER}-php-opcache >/dev/null 2>&1
            
            # 2. Localiza o arquivo oficial (o cPanel pode nomear como opcache.ini ou 10-opcache.ini)
            INI_FILE=$(ls /opt/cpanel/${VER}/root/etc/php.d/*opcache.ini | head -n 1)
            
            # 3. Se não existir, cria o padrão
            if [ -z "$INI_FILE" ]; then
                INI_FILE="/opt/cpanel/${VER}/root/etc/php.d/10-opcache.ini"
                echo "zend_extension=opcache.so" > "$INI_FILE"
            fi

            # 4. Mantém apenas a linha zend_extension e limpa o resto para aplicar o tune
            sed -i '/^[^zend_extension]/d' "$INI_FILE"
            echo "$OPC_TUNE" >> "$INI_FILE"
            chmod 644 "$INI_FILE"
        done

        # --- Reinicialização Única ---
        echo "Reiniciando serviços..."
        pkill -9 php-fpm >/dev/null 2>&1
        /scripts/restartsrv_httpd --quiet
        /scripts/restartsrv_apache_php_fpm --quiet
        
        [ -x /usr/sbin/cagefsctl ] && cagefsctl --force-update >/dev/null 2>&1
        echo "Instalação finalizada."
        ;;

    --test)
        echo "Status OPcache:"
        for phpbin in /usr/local/bin/ea-php[0-9][0-9]; do
            [ -f "$phpbin" ] || continue
            NAME=$(basename $phpbin)
            # Teste direto via módulo carregado
            if $phpbin -m | grep -qi "Zend OPcache"; then
                STATUS="\e[32mATIVO\e[0m"
                MEM=$($phpbin -r "echo opcache_get_status(false)['memory_usage']['used_memory']>>20;" 2>/dev/null)MB
            else
                STATUS="\e[31mOFF\e[0m"
                MEM="---"
            fi
            printf "%-15s | %-10s | %-10s\n" "$NAME" "$STATUS" "$MEM"
        done
        ;;
esac

# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/opcache.sh") --test