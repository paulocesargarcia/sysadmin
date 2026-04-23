#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2016,SC2002,SC2045
# Análise forense: load alto em AlmaLinux 9 + cPanel (+ CloudLinux quando presente)
# Gera relatório local + upload opcional (tmptext.com)
#
# Uso remoto:
#   bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-load-analyzer.sh")
# Instalação:
#   chmod 700 /root/cpanel-load-analyzer.sh

# ============================================================
# PROMPT PARA ANÁLISE (COPIAR E COLAR JUNTO COM O RELATÓRIO)
# ============================================================
read -r -d '' PROMPT_ANALISE <<'PROMPT' || true
CONTEXTO E REGRAS:
- Este é um RELATÓRIO FORENSE de carga (load) em um servidor cPanel, AlmaLinux 9, com possível CloudLinux (LVE, MySQL Governor).
- O objetivo é apontar a CAUSA DO LOAD ALTO e qual USUÁRIO cPanel (conta) está no centro do problema, correlacionando:
  (1) snapshot ao vivo, (2) janela histórica de ~1h (sar, lveinfo), (3) processos, (4) I/O, (5) MySQL, (6) web (Apache/PHP-FPM), (7) e-mail (Exim), (8) OOM/disk na kernel/journal.
- Não invente números: cite apenas o que constar no relatório.
- Diferencie: load alto por CPU, por IOWAIT (D state), por saturação de MySQL, por pico de conexões HTTP, por fila de e-mail, por falha de disco/OOM.
- Se CloudLinux não estiver presente, explique a limitação e baseie o diagnóstico em ps, mysql, Apache, I/O, rede.

ESTRUTURA OBRIGATÓRIA DA RESPOSTA:
1) Causa provável (1 frase) + subtipo (CPU/IO/MYSQL/HTTP/EXIM/OOM/OUTRO)
2) Usuário(s) cPanel mais prováveis (com evidência: LVE, ps, DB, vhost, Exim)
3) Próximos 3 passos de confirmação (comandos)
4) Ações de mitigação (só leitura neste script; se sugerir tuning, cite arquivo e risco)
PROMPT

# ============================================================
# VERIFICAÇÃO DE DEPENDÊNCIAS
# ============================================================
DEPENDENCIAS=(
	"bash"
	"curl"
	"elinks"
	"awk"
	"sort"
	"uniq"
	"head"
	"tail"
	"cut"
	"tr"
	"wc"
	"ss"
	"ps"
	"date"
	"mpstat"    # sysstat
	"vmstat"     # sysstat
	"iostat"     # sysstat
	"pidstat"    # sysstat
	"sar"        # sysstat
	"whmapi1"    # cpanel
)

verificar_dependencias() {
	local faltantes=()
	echo ">> Verificando dependências (cpanel-load-analyzer)…"
	for cmd in "${DEPENDENCIAS[@]}"; do
		if [[ "$cmd" == /* ]]; then
			test -f "$cmd" || faltantes+=("$cmd")
		else
			command -v "$cmd" >/dev/null 2>&1 || faltantes+=("$cmd")
		fi
	done
	if ((${#faltantes[@]} > 0)); then
		echo "----------------------------------------------------------------"
		echo "ERRO: Dependências ausentes:"
		for c in "${faltantes[@]}"; do
			echo "  [X] $c"
		done
		echo ""
		echo "Sugestão: dnf -y install sysstat elinks cpanel* (se WHM) ou copiar whmapi1 do servidor cPanel."
		echo "----------------------------------------------------------------"
		exit 1
	fi
	echo ">> Dependências OK."
}

# ============================================================
# Funções (evitam '|' no campo CMD do heredom)
# ============================================================

f_section_header() { echo "=================================="; }

f_contexto_geral() {
	f_section_header
	echo "== DATA / HOST =="
	date
	hostname
	echo
	echo "== NPROC =="
	nproc
	echo
	echo "== LOAD =="
	cat /proc/loadavg
	uptime
	echo
	echo "== OS =="
	cat /etc/os-release
	echo
	echo "== KERNEL =="
	uname -a
	echo
	echo "== cPanel (whmapi1) =="
	whmapi1 version 2>&1 | grep -Ei "version|release" | head -10 || true
}

f_cpu_snapshot() {
	f_section_header
	echo "== TOP (snapshot) =="
	top -b -n1 -c -w 512 2>&1 | head -40
	echo
	echo "== MPSTAT 1s x3 =="
	mpstat -P ALL 1 3
	echo
	echo "== VMSTAT 1s x5 =="
	vmstat 1 5
}

# sar: desde 1h atrás até agora (GNU date, Alma)
f_sar_cpu_hist() {
	local s
	s="$(date -d '1 hour ago' '+%H:%M' 2>/dev/null || true)"
	[[ -z "$s" ]] && s="00:00"
	f_section_header
	echo "== SAR CPU (desde $s) =="
	sar -u -s "$s" 2>&1 | tail -200 || true
}

f_sar_load_hist() {
	local s
	s="$(date -d '1 hour ago' '+%H:%M' 2>/dev/null || true)"
	[[ -z "$s" ]] && s="00:00"
	f_section_header
	echo "== SAR FILA/LOAD (desde $s) =="
	sar -q -s "$s" 2>&1 | tail -120 || true
}

f_sar_io_hist() {
	local s
	s="$(date -d '1 hour ago' '+%H:%M' 2>/dev/null || true)"
	[[ -z "$s" ]] && s="00:00"
	f_section_header
	echo "== SAR I/O (desde $s) =="
	sar -b -s "$s" 2>&1 | tail -120 || true
}

f_top_procs() {
	f_section_header
	echo "== PS por %CPU =="
	ps -eo user:30,pid,ppid,pcpu,pmem,stat,args --sort=-pcpu 2>&1 | head -30
	echo
	echo "== PS por %MEM =="
	ps -eo user:30,pid,ppid,pcpu,pmem,stat,args --sort=-pmem 2>&1 | head -30
}

f_proc_d_state() {
	f_section_header
	echo "== Processos D (I/O) =="
	ps -eo state,user:30,pid,args 2>&1 | awk 'NR==1 || $1 ~ /^D/' | head -40
	echo
	echo "== Zumbis =="
	ps -eo state,user:30,pid,args 2>&1 | awk 'NR==1 || $1 ~ /^Z/' | head -20
}

f_user_aggregate() {
	f_section_header
	echo "== Agregado por USUÁRIO: soma %CPU, %MEM, procs, RSS MB =="
	ps -eo user:30,pcpu,pmem,rss --no-headers 2>&1 | awk '{
		u=$1; c[u]+=($2+0); m[u]+=($3+0); r[u]+=($4+0); n[u]++
	} END {
		for (u in c)
			printf "%.1f\t%.1f\t%d\t%8.0f\t%s\n", c[u], m[u], n[u], r[u]/1024, u
	}' | sort -k1,1gr | head -25
}

f_lve_block() {
	f_section_header
	if ! command -v lveinfo >/dev/null 2>&1; then
		echo "lveinfo não instalado (provável Alma sem CloudLinux)."
		return 0
	fi
	echo "== LVE: uso CPU 1h (top) =="
	lveinfo --period=1h --by-usage cpu --display-username --limit=20 2>&1 || true
	echo
	echo "== LVE: uso IO 1h =="
	lveinfo --period=1h --by-usage io --display-username --limit=20 2>&1 || true
	echo
	echo "== LVE: IOPS 1h =="
	lveinfo --period=1h --by-usage iops --display-username --limit=20 2>&1 || true
	echo
	echo "== LVE: MEP 1h =="
	lveinfo --period=1h --by-usage mep --display-username --limit=20 2>&1 || true
	echo
	echo "== LVE: faltas CPU 1h =="
	lveinfo --period=1h --by-fault cpu --display-username 2>&1 | head -50 || true
	echo
	echo "== LVE: faltas IO 1h =="
	lveinfo --period=1h --by-fault io --display-username 2>&1 | head -50 || true
	echo
	echo "== lveinfo (tempo real, top 30) =="
	{ lveinfo --show-all --style admin --limit 30 2>&1 | head -60; } || true
}

f_lvectl() {
	if command -v lvectl >/dev/null 2>&1; then
		f_section_header
		echo "== lvectl list (somente não-default; default=SPEED 100 PMEM 1024M) =="
		{ lvectl list 2>&1 | awk 'NR<=1 || ($2!="100" || $3!="1024M")' | head -60; } || true
	else
		echo "(lvectl indisponível)"
	fi
}

f_dbctl() {
	f_section_header
	if ! command -v dbctl >/dev/null 2>&1; then
		echo "dbctl indisponível (MySQL Governor requer CloudLinux+Governor)."
		return 0
	fi
	echo "== dbctl list-restricted (throttlados agora) =="
	{ dbctl list-restricted 2>&1 | head -40; } || true
	echo
	echo "== dbctl list --pretty (somente contas com limite != default) =="
	# Mostra cabeçalho + linhas cujo limite de CPU não é o padrão (400/380/350/300)
	{ dbctl list --pretty 2>&1 | awk 'NR<=2 || ($0 !~ /400\/380\/350\/300/)' | head -40; } || true
	echo
	echo "== Total de contas dbctl =="
	{ dbctl list --pretty 2>&1 | awk 'NR>2 {n++} END{print n" contas"}'; } || true
}

f_mysql() {
	f_section_header
	echo "== mysqladmin processlist =="
	mysqladmin processlist 2>&1 | head -80 || true
	echo
	echo "== Queries ativas (não-Sleep) >5s =="
	mysql -Nse "SELECT user,host,db,time,state,LEFT(info,200) FROM information_schema.processlist WHERE command<>'Sleep' AND time>5 ORDER BY time DESC LIMIT 30" 2>&1 || echo "(mysql indisponível ou falha de credencial)"
	echo
	echo "== mysqladmin extended (trecho) =="
	mysqladmin extended-status 2>&1 | grep -Ei 'Threads_running|Slow_queries|Questions|Innodb_row_lock|Threads_connected|Aborted' || true
	echo
	local slowf
	slowf="$(mysql -Nse "SELECT COALESCE(@@slow_query_log_file,'')" 2>/dev/null | tr -d '\r' || true)"
	if [[ -n "$slowf" && -f "$slowf" ]]; then
		echo "== slow_query_log (tail) $slowf =="
		tail -50 "$slowf" 2>&1
	else
		echo "== slow log: não habilitado ou arquivo inacessível =="
		mysql -Nse "SELECT @@slow_query_log, @@slow_query_log_file" 2>&1 || true
	fi
}

f_apache() {
	f_section_header
	echo "== apachectl -M =="
	(apachectl -M 2>&1) | head -30 || true
	echo
	if command -v elinks >/dev/null 2>&1; then
		echo "== apachectl fullstatus =="
		COLUMNS=200 apachectl fullstatus 2>&1 | head -120
	else
		echo "elinks ausente: fullstatus indisponível"
	fi
}

f_phpfpm_count() {
	f_section_header
	echo "== Contagem de workers PHP-FPM por usuário =="
	ps -eo user:30,args 2>&1 | awk '/php-fpm/ && $0 !~ /master/ { c[$1]++ } END { for (u in c) print c[u], u }' | sort -rn | head -20
}

f_phpfpm_slow() {
	f_section_header
	echo "== PHP-FPM slow logs (tail) =="
	shopt -s nullglob
	local f
	local found=0
	local paths=(
		/opt/cpanel/ea-php*/root/var/log/php-fpm/*slow*.log
		/opt/cpanel/ea-php*/root/usr/var/log/php-fpm/*slow*.log
		/var/cpanel/logs/phpfpm/*slow*.log
		/var/cpanel/logs/phpfpm/*/slow*.log
		/var/log/php-fpm/*slow*.log
	)
	for f in "${paths[@]}"; do
		[[ -f "$f" ]] || continue
		[[ -s "$f" ]] || continue
		found=1
		echo "--- $f ---"
		tail -30 "$f" 2>&1
	done
	shopt -u nullglob
	if (( ! found )); then
		echo "(nenhum slow log com conteúdo encontrado)"
		echo "Paths verificados:"
		printf '  %s\n' "${paths[@]}"
		echo "Dica: pools PHP-FPM podem ter request_slowlog_timeout=0 (desabilitado)."
	fi
}

f_io() {
	f_section_header
	echo "== IOSTAT =="
	iostat -xz 1 3
	if command -v iotop >/dev/null 2>&1; then
		echo
		echo "== IOTOP (batched) =="
		iotop -b -n 3 -o 2>&1 | head -40
	else
		echo "(iotop não instalado: dnf install -y iotop)"
	fi
	echo
	echo "== PIDSTAT I/O 1s x3 =="
	pidstat -d 1 3
}

f_ss_summary() { ss -s; }

f_top_ips_80_443() {
	f_section_header
	echo "== Top IPs clientes (estabelecido; local :80 ou :443) =="
	# ss -Htn state established => colunas: Recv-Q Send-Q LOCAL PEER
	# $3 = local (servidor), $4 = peer (cliente). Filtrar local em 80/443.
	{ ss -Htn state established 2>&1 | awk '($3 ~ /:80$/ || $3 ~ /:443$/) {
		peer = $4
		if (peer ~ /^\[/) {
			# [ipv6]:port
			if (match(peer, /^\[[^]]+\]/)) { ip = substr(peer, RSTART+1, RLENGTH-2) } else { ip = peer }
		} else {
			# a.b.c.d:port
			sub(/:[0-9]+$/, "", peer)
			ip = peer
		}
		if (ip != "") c[ip]++
	}
	END { for (a in c) print c[a], a }' | sort -rn | head -20; } || true
}

f_ss_pids_to_users() {
	f_section_header
	echo "== Conexões com processo (amostra: portas 80/443) =="
	{ ss -tpn state established 2>&1 | awk '($3 ~ /:80$/ || $3 ~ /:443$/) {print}' | head -40; } || true
}

f_exim() {
	f_section_header
	if ! command -v exim >/dev/null 2>&1; then
		echo "exim não encontrado"
		return 0
	fi
	echo "== exim -bpc (total na fila) =="
	exim -bpc 2>&1
	echo
	if command -v exiqsumm >/dev/null 2>&1; then
		echo "== exim -bp | exiqsumm -c (domínios na fila) =="
		{ exim -bp 2>/dev/null | exiqsumm -c 2>&1 | head -25; } || true
	fi
}

f_exim_sasl() {
	f_section_header
	echo "== Top A=dovecot_login (amostra exim mainlog) =="
	if [[ -f /var/log/exim_mainlog ]]; then
		tail -200000 /var/log/exim_mainlog 2>&1 | awk '/A=dovecot_login/ {
			for (i=1;i<=NF;i++) if ($i ~ /^A=dovecot_login:/) print $i
		}' | sort | uniq -c | sort -rn | head -15
	else
		echo "Arquivo /var/log/exim_mainlog não encontrado"
	fi
}

f_exim_cwd() {
	f_section_header
	echo "== Top cwd= origem (amostra exim mainlog) =="
	if [[ -f /var/log/exim_mainlog ]]; then
		tail -200000 /var/log/exim_mainlog 2>&1 | grep "cwd=" 2>&1 | awk -F"cwd=" '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -15
	else
		echo "Arquivo /var/log/exim_mainlog não encontrado"
	fi
}

f_logs_kernel() {
	f_section_header
	echo "== dmesg (tail) =="
	dmesg -T 2>&1 | tail -100
}

f_logs_journal() {
	f_section_header
	echo "== journalctl err (1h) =="
	journalctl --since "1 hour ago" -p err --no-pager 2>&1 | tail -200
}

f_logs_cpanel() {
	f_section_header
	for p in /usr/local/apache/logs/error_log /usr/local/cpanel/logs/error_log; do
		if [[ -f "$p" ]]; then
			echo "== tail $p =="
			tail -100 "$p" 2>&1
			echo
		fi
	done
}

f_imunify360() {
	if ! command -v imunify360-agent >/dev/null 2>&1; then
		echo "(Imunify360 não presente no PATH)"
		return 0
	fi
	f_section_header
	echo "== imunify360-agent version =="
	{ imunify360-agent version 2>&1 | head -5; } || true
	echo
	echo "== imunify360-agent rstatus =="
	{ imunify360-agent rstatus 2>&1 | head -30; } || true
	echo
	echo "== Incidentes última 1h (imunify360-agent get --period 1h) =="
	{ imunify360-agent get --period 1h 2>&1 | head -30; } || true
	echo
	echo "== Top IPs na blacklist local (limit 30) =="
	{ imunify360-agent ip-list local list --purpose drop --limit 30 2>&1 | head -40; } || true
	echo
	echo "== IPs em captcha (limit 20) =="
	{ imunify360-agent ip-list local list --purpose captcha --limit 20 2>&1 | head -30; } || true
}

# Resumo final: heurística curta; analista/LLM cruza com seções anteriores
f_resumo() {
	local n l1 l2 l3 nproc
	nproc="$(nproc 2>/dev/null || echo "?")"
	read -r l1 l2 l3 _ < /proc/loadavg 2>/dev/null || true
	f_section_header
	echo "== RESUMO CONSOLIDADO (heurístico) =="
	echo "nproc(cores)=$nproc  load(1/5/15)=$l1 $l2 $l3"
	echo
	echo "-- Top 5 usuários (soma %CPU snapshot) --"
	ps -eo user:30,pcpu --no-headers 2>&1 | awk 'NF>=2 { c[$1]+=($2+0) } END { for (u in c) if (c[u]>0) printf "%.1f %s\n", c[u], u }' | sort -gr | head -5
	echo
	if command -v lveinfo >/dev/null 2>&1; then
		echo "-- LVE: top 5 CPU (1h) se disponível --"
		lveinfo --period=1h --by-usage cpu --display-username --limit=5 2>&1 | head -12 || true
		echo
	fi
	echo "-- MySQL: usuários com threads não-sleeping --"
	mysql -Nse "SELECT user, COUNT(*) FROM information_schema.processlist WHERE command<>'Sleep' GROUP BY user ORDER BY COUNT(*) DESC" 2>&1 | head -10 || true
	echo
	echo "-- Processos D: contagem por usuário (se houver) --"
	ps -eo state,user:30 2>&1 | awk 'NR>1 && $1=="D" {a[$2]++} END{for(u in a) print a[u],u}' | sort -rn | head -10
	echo
}

f_print_prompt() {
	f_section_header
	echo "=== INSTRUÇÕES PARA ANÁLISE (cole este bloco com o .txt) ==="
	printf '%s\n' "$PROMPT_ANALISE"
}

# ============================================================
# main
# ============================================================
verificar_dependencias

RELATORIO="loadanalyzer_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
export PROMPT_ANALISE

read -r -d '' COMANDOS <<'EOF' || true
00 Instruções p/ análise LLM|f_print_prompt
1 Contexto|f_contexto_geral
2 CPU snapshot|f_cpu_snapshot
2b SAR CPU 1h|f_sar_cpu_hist
2c SAR carga 1h|f_sar_load_hist
2d SAR I/O 1h|f_sar_io_hist
3 Processos|f_top_procs
3b D state / zumbis|f_proc_d_state
4 Agregado usuários|f_user_aggregate
5 CloudLinux LVE|f_lve_block
5b lvectl|f_lvectl
6 MySQL Governor|f_dbctl
6b MySQL|f_mysql
7 Apache|f_apache
7b PHP-FPM|f_phpfpm_count
7c PHP-FPM slow|f_phpfpm_slow
8 I/O|f_io
9 Rede (ss -s)|f_ss_summary
9b Top IPs 80/443|f_top_ips_80_443
9c ss -tp (amostra)|f_ss_pids_to_users
10 Exim|f_exim
10b Exim sasl|f_exim_sasl
10c Exim cwd|f_exim_cwd
11 dmesg|f_logs_kernel
11b journal|f_logs_journal
11c error logs|f_logs_cpanel
11d Imunify|f_imunify360
12 Resumo|f_resumo
EOF

{
	echo "Relatório Load Analyzer (cpanel) - $(date)"
	echo "==================================="
} >"$RELATORIO"

while IFS='|' read -r DESC CMD; do
	[[ -z "${DESC// }" ]] && continue
	{
		echo ""
		f_section_header
		echo "## $DESC"
		echo "Comando: $CMD"
		echo "-----------------------------------"
		# shellcheck disable=SC2086
		eval "$CMD" 2>&1 || echo "Erro ao executar: $DESC (continuando)"
	} | tee -a "$RELATORIO"
done <<<"$COMANDOS"

echo "Relatório gerado: $RELATORIO"

# Upload opcional (falha de rede não interrompe)
RESP=$(curl -s -F "file=@$RELATORIO" https://tmptext.com/api/upload) || true
if [[ -n "$RESP" && "$RESP" =~ \"url\" ]]; then
	URL=$(echo "$RESP" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
	EXPIRE_RAW=$(echo "$RESP" | sed -n 's/.*"expires_at":"\([^"]*\)".*/\1/p')
	EXPIRE=$(echo "$EXPIRE_RAW" | awk -F- '{print $3"/"$2"/"$1}')
	echo "URL: $URL"
	echo "EXPIRE: $EXPIRE"
else
	echo "Upload opcional falhou; use o arquivo local: $RELATORIO"
fi

# Como usar remote:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/cpanel-load-analyzer.sh")
