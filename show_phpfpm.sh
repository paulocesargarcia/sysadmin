#!/usr/bin/env bash

# Exibe conexões php-fpm no formato: ip_origem - ip_destino - user
netstat -tnp 2>/dev/null | awk '
/php-fpm/ {
  split($7,a,"/");
  pid=a[1];
  cmd="ps -o user= -p " pid;
  cmd | getline user; close(cmd);
  print $4 " - " $5 " - " user
}'


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/show_phpfpm.sh")
