#!/bin/bash

# Define o arquivo de saída com timestamp
OUT="/root/pve_report_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

# Função para logar no arquivo e no terminal simultaneamente
log() {
    echo -e "$*" | tee -a "$OUT"
}

run_cmd() {
    log "\n--- $1 ---"
    eval "$2" | tee -a "$OUT"
}

log "=== PROXMOX SYSTEM AUDIT - $(date) ==="
log "Hostname: $(hostname)"
log "Relatório: $OUT"

# 1. Kernel & CPU
run_cmd "KERNEL & CPU" "uname -a; lscpu | grep -E 'Model name|Core\(s\) per socket|Thread\(s\) per core|L[1-3] cache|Vulnerability'"
run_cmd "CPU VULNERABILITIES" "grep . /sys/devices/system/cpu/vulnerabilities/*"

# 2. Memória & NUMA
run_cmd "MEMORY" "free -h"
run_cmd "NUMA TOPOLOGY" "numactl --hardware 2>/dev/null || echo 'numactl not installed'"

# 3. PCIe & Controladoras
run_cmd "PCIE DEVICES" "lspci -nnk | grep -iE 'vga|ethernet|storage|sas|raid|nvme' -A 2"

# 4. Storage (Físico e ZFS)
run_cmd "BLOCK DEVICES" "lsblk -o NAME,SIZE,TYPE,ROTA,DISC-GRAN,MODEL,SERIAL"

if command -v zpool >/dev/null; then
    run_cmd "ZFS POOLS" "zpool list -v"
    run_cmd "ZFS CONFIG" "zpool get all | grep -E 'ashift|fragmentation|capacity|freeing'"
    run_cmd "ZFS ARC" "grep '' /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null; arcstat 1 1 2>/dev/null"
fi

# 5. Ceph Status
if command -v ceph >/dev/null; then
    run_cmd "CEPH STATUS" "ceph status"
    run_cmd "CEPH OSD TREE" "ceph osd tree"
    run_cmd "CEPH DF" "ceph df"
fi

# 6. Networking
run_cmd "NETWORK INTERFACES" "ip -br link show"
run_cmd "BRIDGE/VLAN" "bridge vlan show"

log "\n--- NETWORK OFFLOADING ---"
for i in $(ls /sys/class/net/ | grep -v lo); do 
    log "\nInterface: $i"
    ethtool -k "$i" 2>/dev/null | grep -E "segmentation|checksumming|receive-offload" | grep ": on" | tee -a "$OUT"
done

# 7. Proxmox Specifics
run_cmd "PVE VERSION" "pveversion -v"
run_cmd "STORAGE CONFIG" "cat /etc/pve/storage.cfg"

log "\n=== DIAGNOSTIC FINISHED ==="
log "Relatório salvo em: $OUT"


# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/audit-hardware.sh")
