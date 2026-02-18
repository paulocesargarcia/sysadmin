cat << 'EOF' > /tmp/pve_diag.sh
#!/bin/bash
OUT="/root/pve_report_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUT") 2>&1

echo "=== PROXMOX SYSTEM AUDIT - $(date) ==="
echo "--- KERNEL & CPU ---"
uname -a
lscpu | grep -E "Model name|Core\(s\) per socket|Thread\(s\) per core|L[1-3] cache|Vulnerability"
grep . /sys/devices/system/cpu/vulnerabilities/*

echo -e "\n--- MEMORY & NUMA ---"
free -h
numactl --hardware 2>/dev/null || echo "numactl not installed"

echo -e "\n--- PCIE & CONTROLLERS ---"
lspci -nnk | grep -iE "vga|ethernet|storage|sas|raid|nvme" -A 2

echo -e "\n--- STORAGE (PHYSICAL & ZFS) ---"
lsblk -o NAME,SIZE,TYPE,ROTA,DISC-GRAN,MODEL,SERIAL
if command -v zpool >/dev/null; then
    zpool list -v
    zpool get all | grep -E "ashift|fragmentation|capacity|freeing"
    echo "ZFS ARC Max: $(grep "" /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'default')"
    arcstat 1 1 2>/dev/null
fi

echo -e "\n--- CEPH STATUS ---"
if command -v ceph >/dev/null; then
    ceph status
    ceph osd tree
    ceph df
    ceph config dump
fi

echo -e "\n--- NETWORKING ---"
ip -br link show
bridge vlan show
for i in $(ls /sys/class/net/ | grep -v lo); do 
    echo "Offloading for $i:"
    ethtool -k $i | grep -E "segmentation|checksumming|receive-offload" | grep ": on"
done

echo -e "\n--- PROXMOX CONFIG ---"
pveversion -v
cat /etc/pve/storage.cfg

echo "=== DIAGNOSTIC FINISHED ==="
echo "Relatório gerado em: $OUT"
EOF

# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/audit-hardware.sh")