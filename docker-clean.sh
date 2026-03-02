#!/bin/bash

clear
echo "⚠️  ATENÇÃO: LIMPEZA TOTAL DO DOCKER ⚠️"
echo
echo "Este script irá REMOVER PERMANENTEMENTE:"
echo " - Todos os containers (rodando e parados)"
echo " - Todas as imagens"
echo " - Todos os volumes (DADOS SERÃO PERDIDOS)"
echo " - Todas as redes customizadas"
echo " - Cache de build"
echo
echo "Isso pode apagar bancos de dados, arquivos e aplicações."
echo "NÃO há como desfazer."
echo
read -p "Digite 'APAGAR TUDO' para confirmar: " confirmacao

if [ "$confirmacao" != "APAGAR TUDO" ]; then
  echo "Operação cancelada."
  exit 1
fi

echo
echo "Iniciando limpeza..."

docker stop $(docker ps -aq) 2>/dev/null
docker rm -f $(docker ps -aq) 2>/dev/null
docker rmi -f $(docker images -aq) 2>/dev/null
docker volume rm $(docker volume ls -q) 2>/dev/null
docker network rm $(docker network ls -q | grep -v -E "bridge|host|none") 2>/dev/null
docker system prune -a --volumes -f

echo
echo "Docker totalmente limpo."

# sh <(curl -s "https://raw.githubusercontent.com/paulocesargarcia/sysadmin/refs/heads/main/docker-clean.sh")