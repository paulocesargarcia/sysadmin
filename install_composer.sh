#!/usr/bin/env bash
set -euo pipefail

# Configurações
PHP_BIN="${PHP_BIN:-/opt/cpanel/ea-php82/root/usr/bin/php}"
COMPOSER_BIN="/usr/local/bin/composer"
CAGEFS_CFG="/etc/cagefs/conf.d/composer.cfg"
TMP_DIR="/tmp"

echo "[1/6] Verificando PHP CLI em: $PHP_BIN"
if [[ ! -x "$PHP_BIN" ]]; then
  echo "ERRO: PHP CLI não encontrado em $PHP_BIN (ajuste PHP_BIN=...)."
  exit 1
fi

echo "[2/6] Baixando instalador do Composer em $TMP_DIR"
curl -sS https://getcomposer.org/installer -o "$TMP_DIR/composer-setup.php"

echo "[3/6] Instalando Composer usando allow_url_fopen=On"
"$PHP_BIN" -d allow_url_fopen=On "$TMP_DIR/composer-setup.php"

echo "[4/6] Movendo binário para $COMPOSER_BIN"
mv -f composer.phar "$COMPOSER_BIN"
chmod +x "$COMPOSER_BIN"

echo "[5/6] Integrando com CageFS (se aplicável)"
if command -v cagefsctl >/dev/null 2>&1; then
  mkdir -p "$(dirname "$CAGEFS_CFG")"
  cat > "$CAGEFS_CFG" <<'EOF'
[composer]
comment=Composer https://getcomposer.org/
paths=/usr/local/bin/composer
EOF
  cagefsctl --force-update || true
else
  echo "Aviso: CageFS não encontrado, pulando integração."
fi

echo "[6/6] Verificando versão"
"$COMPOSER_BIN" --version

echo "OK: Composer instalado em $COMPOSER_BIN."


# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/install_composer.sh")