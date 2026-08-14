#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# build.sh — genera el proyecto con XcodeGen, compila AIclient (Release) y lo
# instala en /Applications, reemplazando cualquier versión anterior.
#
# Uso:
#   ./build.sh                                # firma ad-hoc (solo corre en este Mac)
#   AICLIENT_TEAM_ID=ABCDE12345 ./build.sh     # firma "Automatic" con tu Team ID
#   AICLIENT_SKIP_CLEAN=1 ./build.sh           # build incremental (sin "clean")
#   AICLIENT_NO_OPEN=1 ./build.sh              # no abrir la app al terminar
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="AIclient"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$SCRIPT_DIR/build/DerivedData"
APP_NAME="AIclient.app"
EXECUTABLE_NAME="AIclient"
DEST_DIR="/Applications"

# --- 0. sanity checks --------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: este script solo puede correr en macOS." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: falta xcodegen. Instálalo con: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: falta xcodebuild. Instala Xcode (y sus Command Line Tools) primero." >&2
  exit 1
fi

# --- 1. (re)generar el .xcodeproj a partir de project.yml --------------------
echo "==> xcodegen generate"
xcodegen generate

# --- 2. firma: automática con tu Team ID si lo defines; si no, ad-hoc --------
SIGNING_ARGS=()
if [[ -n "${AICLIENT_TEAM_ID:-}" ]]; then
  echo "==> Firmando con Team ID: $AICLIENT_TEAM_ID"
  SIGNING_ARGS+=(DEVELOPMENT_TEAM="$AICLIENT_TEAM_ID" CODE_SIGN_STYLE=Automatic)
else
  echo "==> AICLIENT_TEAM_ID no definido: firma ad-hoc (válida solo en este Mac)"
  SIGNING_ARGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
fi

# --- 3. build -----------------------------------------------------------------
BUILD_ACTIONS=(build)
if [[ "${AICLIENT_SKIP_CLEAN:-0}" != "1" ]]; then
  BUILD_ACTIONS=(clean build)
fi

echo "==> xcodebuild ${BUILD_ACTIONS[*]} ($CONFIGURATION)"
xcodebuild \
  -project "AIclient.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}" \
  "${BUILD_ACTIONS[@]}"

# --- 4. localizar el .app producido -------------------------------------------
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: no se encontró $BUILT_APP tras el build." >&2
  exit 1
fi
echo "==> App compilada en: $BUILT_APP"

# --- 5. si ya está corriendo, cerrarla antes de sobrescribirla ---------------
if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
  echo "==> Cerrando instancia de AIclient en ejecución..."
  osascript -e 'tell application "AIclient" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
fi

# --- 6. instalar en /Applications ---------------------------------------------
DEST_APP="$DEST_DIR/$APP_NAME"
if [[ -d "$DEST_APP" ]]; then
  echo "==> Eliminando versión anterior en $DEST_APP"
  rm -rf "$DEST_APP"
fi

echo "==> Copiando a $DEST_APP"
cp -R "$BUILT_APP" "$DEST_APP"

# Por si el .app arrastra atributo de cuarentena (p. ej. si lo moviste vía
# AirDrop/red antes de correr esto) — un build local normalmente no lo tiene.
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "==> Instalado en $DEST_APP"

if [[ "${AICLIENT_NO_OPEN:-0}" != "1" ]]; then
  echo "==> Abriendo AIclient..."
  open "$DEST_APP"
fi

echo "==> Listo."
