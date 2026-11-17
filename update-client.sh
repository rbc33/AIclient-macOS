#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# update-client.sh — aplica un AIclient-build.zip (el que te pasa Claude con
# cambios) sobre este repo y, opcionalmente, hace commit + push + release.
#
# Uso:
#   ./update-client.sh                          # solo copia el zip encima del repo
#   ./update-client.sh "mensaje"                # + commit + push
#   ./update-client.sh "mensaje" 1.0.1          # + commit + push + ./release.sh 1.0.1
#   ./update-client.sh "mensaje" 1.0.0 --replace  # rehace una release ya publicada
#
# Qué zip usa: AICLIENT_ZIP=/ruta/al.zip si lo defines; si no, el
# AIclient-build*.zip más reciente de ~/code/swift o ~/Downloads.
# Una vez aplicado, el zip se mueve a la Papelera para que una ejecución
# posterior no vuelva a aplicar uno viejo encima de cambios más nuevos.
#
# El zip no trae .git, build/ ni dist/: tu historial y tus builds no se tocan.
# Tampoco borra nada: solo añade o sobrescribe archivos.
# -----------------------------------------------------------------------------

# Todo va dentro de main() y se llama en la última línea: bash lee el script
# entero antes de ejecutar nada, así que no pasa nada si el propio zip trae
# una versión nueva de este archivo y la copia encima mientras corre.
main() {
  local script_dir zip msg version replace
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir"

  msg="${1:-}"
  version="${2:-}"
  replace="${3:-}"

  # --- 1. localizar el zip -----------------------------------------------------
  zip="${AICLIENT_ZIP:-}"
  if [[ -z "$zip" ]]; then
    # shellcheck disable=SC2012  # nombres controlados; ls -t da el más reciente
    zip="$(ls -t "$HOME"/code/swift/AIclient-build*.zip "$HOME"/Downloads/AIclient-build*.zip 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$zip" || ! -f "$zip" ]]; then
    echo "error: no encuentro ningún AIclient-build*.zip en ~/code/swift ni en ~/Downloads." >&2
    echo "       Pásalo a mano: AICLIENT_ZIP=/ruta/al.zip ./update-client.sh ..." >&2
    exit 1
  fi
  echo "==> Aplicando $zip"

  # --- 2. descomprimir y copiar encima del repo --------------------------------
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

  # Que no se vuelva a aplicar este mismo zip la próxima vez.
  mv "$zip" "$HOME/.Trash/$(basename "$zip" .zip)-$(date +%Y%m%d-%H%M%S).zip" 2>/dev/null || true

  echo "==> Cambios aplicados:"
  git status --short

  # --- 3. commit + push (si se pasó mensaje) -----------------------------------
  if [[ -z "$msg" ]]; then
    echo
    echo "==> Listo (sin commit). Para commit + push + release:"
    echo "    ./update-client.sh \"mensaje\" X.Y.Z"
    return
  fi

  git add -A
  if git diff --cached --quiet; then
    echo "==> No hay cambios que commitear"
  else
    git commit -q -m "$msg"
    echo "==> Commit: $msg"
  fi
  git pull -q --rebase origin main
  git push -q origin HEAD:main
  echo "==> Push hecho"

  # --- 4. release (si se pasó versión) -----------------------------------------
  if [[ -n "$version" ]]; then
    if [[ -n "$replace" ]]; then
      ./release.sh "$version" "$replace"
    else
      ./release.sh "$version"
    fi
  fi
}

main "$@"
exit
