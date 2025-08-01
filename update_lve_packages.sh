#!/usr/bin/env bash
NEW_SPEED="200%"
NEW_PMEM="2G"
NEW_IO="2048"
NEW_IOPS="1024"
NEW_EP="20"
NEW_NPROC="100"

lvectl package-list | tail -n +2 | awk '{ print $1 }' | while read -r PKG; do
  if [ "$PKG" = "maxdomin_Avanzado" ]; then
    echo "Atualizando $PKG com configuração customizada"
    lvectl package-set "$PKG" \
      --speed="$NEW_SPEED" \
      --pmem="$NEW_PMEM" \
      --io="$NEW_IO" \
      --iops="$NEW_IOPS" \
      --ep="$NEW_EP" \
      --nproc="$NEW_NPROC"
  else
    echo "Pulando $PKG"
  fi
done

lvectl apply all
