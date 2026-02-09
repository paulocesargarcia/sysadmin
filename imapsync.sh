#!/bin/sh

CONF="imapsync.conf"
CPANEL_ADDPOP="/scripts/addpop"

MODE="$1"

# valida imapsync
command -v imapsync >/dev/null 2>&1 || {
    echo "ERRO: imapsync não instalado."
    exit 1
}

# valida addpop
[ "$MODE" = "--create" ] && [ ! -x "$CPANEL_ADDPOP" ] && {
    echo "ERRO: /scripts/addpop não encontrado."
    exit 1
}

# cria conf exemplo
if [ ! -f "$CONF" ]; then
cat <<EOF > "$CONF"
[origem]
host=mail.origem.com
# ssl=yes   -> IMAPS (porta 993). Omitir ou ssl=no -> STARTTLS (porta 143)

[destino]
host=mail.destino.com
# ssl=yes   -> IMAPS (porta 993). Omitir ou ssl=no -> STARTTLS (porta 143)

[email]
usuario@dominio.com,senha
EOF
    echo "Arquivo $CONF criado."
    exit 0
fi

ORIGEM=$(awk -F= '/^\[origem\]/{f=1} f&&/^host=/{print $2;f=0}' "$CONF")
DESTINO=$(awk -F= '/^\[destino\]/{f=1} f&&/^host=/{print $2;f=0}' "$CONF")
ORIGEM_SSL=$(awk -F= '/^\[origem\]/{f=1} f&&/^ssl=/{print $2;f=0}' "$CONF")
DESTINO_SSL=$(awk -F= '/^\[destino\]/{f=1} f&&/^ssl=/{print $2;f=0}' "$CONF")

# SSL/TLS por host: ssl=yes -> --ssl (porta 993), omitido ou ssl=no -> --tls (porta 143)
SSL1="--tls1"
[ "$ORIGEM_SSL" = "yes" ] && SSL1="--ssl1"
SSL2="--ssl2"
[ "$DESTINO_SSL" = "no" ] && SSL2="--tls2"

awk '
/^\[email\]/{f=1;next}
/^\[/{f=0}
f && NF
' "$CONF" | while IFS=',' read email senha
do
    user=${email%@*}
    domain=${email#*@}

    if [ "$MODE" = "--create" ]; then
        echo "Criando conta $email"
        $CPANEL_ADDPOP "$email" "$senha"
        continue
    fi

    if [ "$MODE" = "--sync" ]; then
        imapsync \
            --host1 "$ORIGEM" --user1 "$email" --password1 "$senha" \
            --host2 "$DESTINO" --user2 "$email" --password2 "$senha" \
            --nofoldersizes --addheader --skipsize \
            --syncinternaldates $SSL1 $SSL2
    fi
done


# Como usar este script remotamente:
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/imapsync.sh") --create
# bash <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/main/imapsync.sh") --sync