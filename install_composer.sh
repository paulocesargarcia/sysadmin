#!/usr/bin/env bash
set -euo pipefail

COMPOSER_BIN="/usr/local/bin/composer"

# Detecta a última versão do PHP EA instalada
detect_php() {
  local php_path
  php_path=$(ls -d /opt/cpanel/ea-php*/root/usr/bin/php 2>/dev/null | sort -V | tail -1)
  
  if [[ -z "$php_path" || ! -x "$php_path" ]]; then
    echo "ERRO: Nenhum PHP EA encontrado em /opt/cpanel/" >&2
    exit 1
  fi
  
  echo "$php_path"
}

# Instala o Composer
install_composer() {
  local php_bin="$1"
  local tmp_installer="/tmp/composer-setup.php"
  
  echo "Baixando instalador do Composer..."
  curl -sS https://getcomposer.org/installer -o "$tmp_installer"
  
  echo "Instalando Composer..."
  "$php_bin" -d allow_url_fopen=On "$tmp_installer" --install-dir=/usr/local/bin --filename=composer
  
  chmod +x "$COMPOSER_BIN"
  rm -f "$tmp_installer"
}

# Integra com CageFS (CloudLinux)
setup_cagefs() {
  if ! command -v cagefsctl >/dev/null 2>&1; then
    return
  fi
  
  echo "Integrando com CageFS..."
  mkdir -p /etc/cagefs/conf.d
  cat > /etc/cagefs/conf.d/composer.cfg <<'EOF'
[composer]
comment=Composer https://getcomposer.org/
paths=/usr/local/bin/composer
EOF
  cagefsctl --force-update || true
}

# Verifica se é CloudLinux
is_cloudlinux() {
  [[ -f /etc/cloudlinux-release ]]
}

# Main
main() {
  if ! is_cloudlinux; then
    echo "AVISO: Este script é otimizado para CloudLinux."
    echo "Detectado: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    read -rp "Deseja continuar mesmo assim? [s/N] " resp
    [[ "${resp,,}" == "s" ]] || exit 0
  fi
  
  local php_bin
  php_bin=$(detect_php)
  echo "PHP detectado: $php_bin"
  
  install_composer "$php_bin"
  setup_cagefs
  
  echo ""
  "$COMPOSER_BIN" --version
  echo "Composer instalado em $COMPOSER_BIN"
}

main

# Uso: sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/install_composer.sh")
