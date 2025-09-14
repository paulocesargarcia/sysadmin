#!/bin/bash
set -u -o pipefail



whmapi1 listaccts --output=json 2>/dev/null | jq -r '.data.acct[].user' |
while read -r user; do
  uapi --user=$user LangPHP php_get_vhost_versions --output=json | jq -r '.result.data[] | "whmapi1 php_set_vhost_versions version='\''\(.version)'\'' vhost='\''\(.vhost)'\''"' | sort -u
done 



# bash <(curl -fsSL "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/list_php_users.sh") > /root/php_users.log
