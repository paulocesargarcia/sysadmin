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
        echo "Iniciando instalação e configuração..."
        for VER in $PHP_VERSIONS; do
            echo "-> Configurando $VER"
            dnf install -y ${VER}-php-opcache >/dev/null 2>&1
            
            INI_PATH="/opt/cpanel/${VER}/root/etc/php.d/10-opcache.ini"
            echo "$OPC_CONFIG" > "$INI_PATH"
            chmod 644 "$INI_PATH"
        done
        
        # --- REINICIALIZAÇÃO ÚNICA AO FINAL ---
        echo "Reiniciando serviços globalmente..."
        
        # Mata processos FPM para garantir que não restem caches em memória
        pkill -9 php-fpm >/dev/null 2>&1
        
        # Reinicia Apache e o Gerenciador de FPM do cPanel
        /scripts/restartsrv_httpd --quiet
        /scripts/restartsrv_apache_php_fpm --quiet
        
        # Sincronização CloudLinux (se houver)
        if command -v cagefsctl >/dev/null 2>&1; then
            echo "Sincronizando CageFS..."
            cagefsctl --force-update >/dev/null 2>&1
        fi
        
        echo "Operação finalizada."
        ;;
    
    --test)
        echo "Relatório de Status OPcache:"
        echo "------------------------------------------------"
        printf "%-15s | %-10s | %-10s\n" "Versão PHP" "Status" "Memória"
        echo "------------------------------------------------"
        for phpbin in /usr/local/bin/ea-php[0-9][0-9]; do
            if [ -f "$phpbin" ]; then
                VER_NAME=$(basename $phpbin)
                CHECK=$($phpbin -r "echo extension_loaded('Zend OPcache') && opcache_get_status()['opcache_enabled'] ? 'ATIVO' : 'INATIVO';" 2>/dev/null)
                
                if [ "$CHECK" == "ATIVO" ]; then
                    MEM=$($phpbin -r "echo round(opcache_get_status()['memory_usage']['used_memory'] / 1024 / 1024, 1) . 'MB';")
                    printf "%-15s | \e[32m%-10s\e[0m | %-10s\n" "$VER_NAME" "$CHECK" "$MEM"
                else
                    printf "%-15s | \e[31m%-10s\e[0m | %-10s\n" "$VER_NAME" "OFF" "---"
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