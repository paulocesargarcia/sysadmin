#!/bin/bash

OPCACHE_CONF='
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.jit=0
'

for dir in /opt/cpanel/ea-php*/; do
    version=$(basename "${dir%/}")
    PHPROOT="/opt/cpanel/$version/root"
    [ -d "$PHPROOT" ] || continue
    INI="$PHPROOT/etc/php.d/10-opcache.ini"
    FPM="${version}-php-fpm"

    echo "==> $version"

    rpm -q ${version}-php-opcache &>/dev/null || \
        dnf install -y ${version}-php-opcache

    echo "$OPCACHE_CONF" > "$INI"

    systemctl restart "$FPM" 2>/dev/null

    echo "OPcache aplicado em $version"

done

echo "OPcache aplicado em todas as versões EA-PHP."


# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/opcache-install.sh")