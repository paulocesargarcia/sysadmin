#!/usr/bin/env bash
#
# update_all_lve_packages_no_jq.sh
# Atualiza speed, pmem, io, iops, ep e nproc de todos os LVE Packages
# CloudLinux 9.6 + cPanel
# Execute como root

# ====== Defina AQUI seus valores ======
NEW_SPEED="200%"     # ex: 200%
NEW_PMEM="2G"        # ex: 2G ou 2048M
NEW_IO="2048"        # em KB/s (2 MB/s → 2048)
NEW_IOPS="1024"
NEW_EP="20"
NEW_NPROC="100"
# =======================================

# Itera em cada ID (pulando o cabeçalho)
lvectl package-list | awk 'NR>1 { print $1 }' | while read -r PKG_ID; do
  echo "➜ Atualizando $PKG_ID"
  lvectl package-set "$PKG_ID" \
    --speed="$NEW_SPEED" \
    --pmem="$NEW_PMEM" \
    --io="$NEW_IO" \
    --iops="$NEW_IOPS" \
    --ep="$NEW_EP" \
    --nproc="$NEW_NPROC"
done

echo "➜ Aplicando em todos os contêineres LVE…"
lvectl apply all

echo "✅ Todos os packages foram atualizados."


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/update_lve_packages.sh")