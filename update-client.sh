#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# update-client.sh — descomprime un AIclient-build.zip (el que te pasa Claude
# con cambios) y copia sus archivos encima de este repo. Nada más: el commit,
# el push y la release los hace ./release.sh.
#
# Uso:
#   ./update-client.sh
#   AICLIENT_ZIP=/ruta/al.zip ./update-client.sh
#
# Qué zip usa: AICLIENT_ZIP si lo defines; si no, el AIclient-build*.zip más
# reciente de ~/code/swift.
#
# El zip no trae .git, build/ ni dist/: tu historial y tus builds no se tocan.
# No borra nada: solo añade o sobrescribe archivos.
# -----------------------------------------------------------------------------

# Todo va dentro de main() y se llama en la última línea: bash lee el script
# entero antes de ejecutar nada, así que no pasa nada si el propio zip trae
# una versión nueva de este archivo y la copia encima mientras corre.
main() {
  local script_dir zip
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir"

  zip="${AICLIENT_ZIP:-}"
  if [[ -z "$zip" ]]; then
    # shellcheck disable=SC2012  # nombres controlados; ls -t da el más reciente
    zip="$(ls -t "$HOME"/code/swift/AIclient-build*.zip 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$zip" || ! -f "$zip" ]]; then
    echo "error: no encuentro ningún AIclient-build*.zip en ~/code/swift." >&2
    echo "       Pásalo a mano: AICLIENT_ZIP=/ruta/al.zip ./update-client.sh" >&2
    exit 1
  fi
  echo "==> Aplicando $zip"

  # Global (no `local`): el trap de EXIT corre cuando main() ya ha terminado.
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  unzip -q -o "$zip" -d "$WORK_DIR"
  if [[ ! -d "$WORK_DIR/AIclient-macOS" ]]; then
    echo "error: el zip no contiene la carpeta AIclient-macOS/." >&2
    exit 1
  fi
  # Sin --delete: nunca borra archivos tuyos que no vengan en el zip.
  rsync -a --exclude ".git/" --exclude "build/" --exclude "dist/" "$WORK_DIR/AIclient-macOS/" ./
  chmod +x ./*.sh

  echo "==> Archivos copiados. Cambios:"
  git status --short
}

main "$@"
exit
