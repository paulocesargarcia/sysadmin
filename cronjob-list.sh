#!/bin/bash

for user in $(ls /var/cpanel/users); do crontab -l -u $user 2>/dev/null | grep -q . && { echo "Usuário: $user"; crontab -l -u $user; echo ""; }; done



# ns59 "bash <(curl -sk https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cronjob-list.sh)" > ns59-log.txt


