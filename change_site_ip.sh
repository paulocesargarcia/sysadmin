MAINIP=$(ip -4 -o addr show | grep -v '127.0.0.1' | awk '{print $4}' | cut -d/ -f1 | head -n1)

for user in $(whmapi1 listaccts | awk '/user: / {print $2}'); do
  whmapi1 setsiteip user=$user ip=$MAINIP
done

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/change_site_ip.sh")
