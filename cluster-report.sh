#!/bin/bash
# =============================================
# Script de Coleta Completa para Documentação Proxmox
# Cluster: BRA-PROX-01 (setik)
# Versão: 2.0
# =============================================
# Execute como root em CADA node
#
# Via GitHub (recomendado):
# bash <(curl -sk https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cluster-report.sh)
#
# Local:
# chmod +x cluster-report.sh && ./cluster-report.sh
# =============================================

NODE=$(hostname -s)
TIMESTAMP=$(date +%Y%m%d-%H%M)
REPORT="/root/cluster-report-FULL-${NODE}-${TIMESTAMP}.txt"

echo "=== INICIANDO COLETA COMPLETA NO NODE ${NODE} ===" | tee -a "$REPORT"
echo "Data: $(date)" | tee -a "$REPORT"
echo "========================================" | tee -a "$REPORT"

{
    echo "=== 1. PVE VERSION ==="
    pveversion -v

    echo -e "\n=== 2. CLUSTER STATUS ==="
    pvecm status
    pvecm nodes
    cat /etc/pve/corosync.conf

    echo -e "\n=== 3. HOSTNAME E HOSTS ==="
    hostname -f
    cat /etc/hosts

    echo -e "\n=== 4. HARDWARE ==="
    lscpu | grep -E "Model name|Socket|Thread|NUMA|CPU\(s\)"
    free -h
    lsblk -o NAME,SIZE,TYPE,MODEL,TRAN

    echo -e "\n=== 5. STORAGE ==="
    pvesm status -v
    pvesm list
    cat /etc/pve/storage.cfg
    ceph -s 2>/dev/null || echo "Ceph: não encontrado"
    ceph osd tree 2>/dev/null
    ceph osd df 2>/dev/null
    ceph df 2>/dev/null

    echo -e "\n=== 6. NETWORK DETALHADA ==="
    ip -br a
    ip -d a
    ip r
    cat /proc/net/bonding/bond0 2>/dev/null || echo "Sem bond0"
    brctl show
    cat /proc/net/vlan/config 2>/dev/null
    cat /etc/network/interfaces

    echo -e "\n=== 7. FIREWALL ==="
    pve-firewall status 2>/dev/null
    iptables-save | head -n 100

    echo -e "\n=== 8. BACKUP JOBS ==="
    cat /etc/pve/jobs.cfg 2>/dev/null

    echo -e "\n=== 9. VMs E CTs DETALHADO ==="
    echo "--- VMs ---"
    qm list
    for vmid in $(qm list | awk 'NR>1 {print $1}'); do
        echo -e "\n[VM ${vmid} Config]"
        qm config $vmid
    done

    echo -e "\n--- CTs ---"
    pct list
    for ctid in $(pct list | awk 'NR>1 {print $1}'); do
        echo -e "\n[CT ${ctid} Config]"
        pct config $ctid
    done

    echo -e "\n=== 10. KERNEL E PERFORMANCE ==="
    uname -a
    pveperf 2>/dev/null || echo "pveperf não executado"

} 2>&1 | tee -a "$REPORT"

echo -e "\n=== RELATÓRIO COMPLETO GERADO ===" | tee -a "$REPORT"
echo "Arquivo: $REPORT" | tee -a "$REPORT"
echo "Tamanho: $(du -h "$REPORT" | cut -f1)" | tee -a "$REPORT"

ls -l "$REPORT"