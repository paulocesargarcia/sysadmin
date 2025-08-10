#!/bin/bash
# Script: remover_limites_lve.sh
# Remove limites de todos os usuários cPanel no LVE

# Percorre todos os usuários do cPanel
whmapi1 listaccts | awk '/^ *user: /{print $2}' | while read u; do
    echo "Removendo limites de: $u"
    lvectl set-user "$u" --unlimited
done

# Ajusta o perfil padrão
echo "Removendo limites do perfil default"
lvectl set default --unlimited

echo "Processo concluído."

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/remover_limites_lve.sh")