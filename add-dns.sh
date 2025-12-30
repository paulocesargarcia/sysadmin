#!/bin/bash

RESOLV="/etc/resolv.conf"

grep -q "^nameserver 1.1.1.1$" "$RESOLV" && exit 0

sed -i '/^search maxdominios.com$/a nameserver 1.1.1.1' "$RESOLV"

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/add-dns.sh")