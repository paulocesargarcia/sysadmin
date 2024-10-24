# max-tools

**max-tools** é uma ferramenta para análise do servidor, automatizando tarefas comuns de administração.

## Instalação

Para instalar ou atualizar o script, execute o comando abaixo:

```bash
sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/max-tools.sh") --install


## Menu

Lista de recursos do script:

```bash
show_help() {
    echo "max-tools - Ferramenta para analise do servidor."
    echo "Uso: $0 [opções]"
    echo "  --help                   Exibe ajuda da ferramenta"
    echo "  --top                    Exibe o uso recursos do servidor"
    echo "  --ip_abuse [ip]          Exibe os usuários com uso excessivo para de um IP"
    echo "  --ip_block [ip]          Bloquear o IP especificado"
    echo "  --list_blocked           Lista todas as regras de bloqueio no firewall"
    echo "  --install                Instalar a versão mais recente"
}

# update-php-ini
bash <(curl -s https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/update-php-ini.sh)