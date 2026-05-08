# Playbook de Contencao de Load Alto (15 minutos)

## 1) Analise

Load alto predominantemente por trafego HTTP (bots/crawlers) em `httpd`, com risco secundario de indisponibilidade por pressao de memoria (OOM) afetando `mariadbd`.

## 1.1) Compatibilidade de comandos

Este playbook usa apenas comandos nativos (`grep -E/-Ei`) e nao depende de `rg`.

## 2) Investigacao (2-4 minutos)

Execute na ordem abaixo para validar causa e alvo:

```bash
date; hostnamectl | grep -E "Operating System|Kernel"
uptime
top -b -n1 | sed -n '1,25p'
mpstat 1 3
vmstat 1 5
```

```bash
apachectl fullstatus 2>/dev/null | grep -Ei "requests/sec|requests currently|CPU Usage|Server load"
ss -ant '( sport = :80 or sport = :443 )' | awk 'NR>1{split($5,a,":"); print a[1]}' | sort | uniq -c | sort -nr | head -30
ps -eo user,pid,ppid,%cpu,%mem,stat,cmd --sort=-%cpu | head -40
```

```bash
lveinfo --by-fault any --period=1h --display-username 2>/dev/null | head -60
lveinfo --by-usage cpu --period=1h --display-username 2>/dev/null | head -60
dbctl list-restricted
mysqladmin proc stat
journalctl -k --since "2 hours ago" | grep -Ei "oom|out of memory|killed process|mariadbd|httpd"
```

## 3) Resolucao (janela de 15 minutos)

### Minuto 0-3: Contencao de impacto (rede + bots)

1. Liste IPs mais agressivos:

```bash
ss -ant '( sport = :80 or sport = :443 )' | awk 'NR>1{split($5,a,":"); print a[1]}' | sort | uniq -c | sort -nr | head -20
```

1. Bloqueie temporariamente apenas o IP ofensivo confirmado conforme seu firewall:

**Opcao A - Imunify360**

```bash
imunify360-agent ip-list local add --purpose drop IP_DO_ABUSO --comment "TEMP_HTTP_ABUSE_1H"
imunify360-agent ip-list local list --purpose drop --by-ip IP_DO_ABUSO
```

**Opcao B - firewalld**

```bash
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='IP_DO_ABUSO' reject"
firewall-cmd --reload
firewall-cmd --list-rich-rules | grep -F "IP_DO_ABUSO"
```

### Minuto 3-6: Descompressao do Apache

1. Reinicio controlado de web stack:

```bash
/scripts/restartsrv_httpd --graceful
/scripts/restartsrv_apache_php_fpm --graceful
```

1. Validacao imediata:

```bash
sleep 5
apachectl fullstatus 2>/dev/null | grep -Ei "requests/sec|requests currently|CPU Usage|Server load"
uptime
```

### Minuto 6-10: Proteger banco e memoria

1. Se `mariadbd` caiu ou esta instavel:

```bash
/scripts/restartsrv_mysql --wait --verbose
mysqladmin ping
mysqladmin proc stat
```

1. Checar memoria/swap apos estabilizacao inicial:

```bash
free -m
vmstat 1 5
journalctl -k --since "30 min ago" | grep -Ei "oom|killed process"
```

### Minuto 10-15: Isolamento por conta cPanel (se necessario)

Se uma conta continuar pressionando recursos, aplique isolamento rapido de LVE:

```bash
# Exemplo: reduzir EP temporariamente para conta suspeita
lvectl set-user brumado --speed=100% --pmem=1024M --io=2048KB/s --iops=1024 --nproc=80 --entryproc=10
lvectl list-user brumado
```

Se o abuso for claramente da aplicacao de uma conta e o impacto estiver alto:

```bash
/scripts/suspendacct brumado "INCIDENT_HTTP_ABUSE_TEMP"
```

Quando estabilizar:

```bash
/scripts/unsuspendacct brumado
```

## 4) Verificacao (saida de crise)

Sistema sai da fase critica quando cumprir todos:

```bash
uptime
mpstat 1 3
apachectl fullstatus 2>/dev/null | grep -Ei "requests/sec|requests currently|CPU Usage|Server load"
mysqladmin ping
dbctl list-restricted
journalctl -k --since "20 min ago" | grep -Ei "oom|killed process"
```

Criterios de normalizacao:

- `load1` aproximando da capacidade do host (referencia: <= numero de vCPU em carga sustentada).
- queda consistente de `requests currently being processed`.
- ausencia de novos eventos OOM.
- `mysqladmin ping` estavel.

## 5) Pos-incidente (obrigatorio)

Coletar evidencias e fechar causa raiz:

```bash
mkdir -p /root/incidentes/load-$(date +%F-%H%M)
cd /root/incidentes/load-$(date +%F-%H%M)
uptime > uptime.txt
top -b -n1 > top.txt
mpstat 1 3 > mpstat.txt
vmstat 1 5 > vmstat.txt
ss -s > ss-s.txt
ss -ant '( sport = :80 or sport = :443 )' > ss-80-443.txt
apachectl fullstatus > apache-fullstatus.txt 2>&1
mysqladmin proc stat > mysql-stat.txt
journalctl -k --since "2 hours ago" > kernel-2h.txt
```

## 6) Hardening recomendado (fora da crise)

**ADVERTENCIA:** alteracoes abaixo mudam comportamento de producao; aplicar em janela controlada e com rollback definido.

1. Ajustar rate limiting/WAF para bots agressivos (Imunify360 + ModSecurity).
2. Revisar tuning de Apache/PHP-FPM para limitar concorrencia explosiva por conta.
3. Revisar tuning de MariaDB (`/etc/my.cnf`) para evitar pressao de memoria em picos.
4. Revisar quotas de mailboxes com erro recorrente (`Disk quota exceeded`).

## 7) Rollback rapido

Se bloqueio excedeu e afetou trafego legitimo:

**Opcao A - Imunify360**

```bash
imunify360-agent ip-list local delete --purpose drop IP_DO_ABUSO
```

**Opcao B - firewalld**

```bash
firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='IP_DO_ABUSO' reject"
firewall-cmd --reload
```

Se LVE foi restritivo demais:

```bash
lvectl apply all
lvectl list-user nome_Usuario
```

