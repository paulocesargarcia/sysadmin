#!/usr/bin/env bash
set -euo pipefail

COMPOSER_BIN="/usr/local/bin/composer"

# Verifica se é CloudLinux
is_cloudlinux() {
  [[ -f /etc/cloudlinux-release ]]
}

# Detecta o PHP disponível no sistema
detect_php() {
  local php_path=""
  
  # CloudLinux/cPanel: busca o PHP EA mais recente
  if is_cloudlinux; then
    php_path=$(ls -d /opt/cpanel/ea-php*/root/usr/bin/php 2>/dev/null | sort -V | tail -1)
  fi
  
  # Fallback: PHP padrão do sistema
  if [[ -z "$php_path" || ! -x "$php_path" ]]; then
    php_path=$(command -v php 2>/dev/null || true)
  fi
  
  if [[ -z "$php_path" || ! -x "$php_path" ]]; then
    echo "ERRO: PHP não encontrado no sistema" >&2
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

# Integra com CageFS (apenas CloudLinux)
setup_cagefs() {
  if ! is_cloudlinux || ! command -v cagefsctl >/dev/null 2>&1; then
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

# Main
main() {
  local os_name
  os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
  echo "Sistema: $os_name"
  
  local php_bin
  php_bin=$(detect_php)
  echo "PHP: $php_bin ($("$php_bin" -v | head -1))"
  
  install_composer "$php_bin"
  setup_cagefs
  
  echo ""
  "$COMPOSER_BIN" --version
  echo "Composer instalado em $COMPOSER_BIN"
}

main

# Uso: sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/install_composer.sh")
