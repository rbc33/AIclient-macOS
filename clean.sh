#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# clean.sh — borra todo lo generado por los scripts de build:
#   build/   DerivedData de Mac e iOS, staging del .dmg, icono extraído
#   dist/    .dmg e .ipa empaquetados
#
# No toca el código, project.yml, apps.json ni el AIclient.xcodeproj
# (ese lo regenera `xcodegen generate` en cada build de todas formas).
#
# Uso: ./clean.sh
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

for dir in build dist; do
  if [[ -e "$dir" ]]; then
    echo "==> Borrando $dir/"
    rm -rf "$dir"
  fi
done

echo "==> Limpio."
