#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# make-dmg.sh — compila AIclient en Release y empaqueta un .dmg de
# arrastrar-y-soltar (la app + un atajo a /Applications), con el icono de la
# propia app como icono del volumen y del archivo .dmg.
#
# Usa `create-dmg` para armar el .dmg (layout de ventana + icono de volumen)
# y `fileicon` para poner el icono al propio archivo .dmg en el Finder. Son
# las mismas herramientas que usa por ejemplo el build.sh de Purrl — mucho
# más fiables que la técnica antigua de incrustar un recurso 'icns' con
# Rez/DeRez: esa técnica depende del resource fork clásico de HFS+ y en
# discos APFS modernos el Finder muchas veces la ignora para el icono del
# propio archivo (aunque el icono del volumen montado sí llegue a verse).
#
# Dependencias (una sola vez):
#   brew install create-dmg   # obligatorio
#   brew install fileicon     # opcional — solo para el icono del .dmg en sí
#
# Uso:
#   ./make-dmg.sh                              # build + firma ad-hoc + dmg
#   AICLIENT_TEAM_ID=ABCDE12345 ./make-dmg.sh  # firma "Automatic" con tu Team ID
#   AICLIENT_SKIP_CLEAN=1 ./make-dmg.sh        # build incremental (sin "clean")
#
# Nota sobre firma y Gatekeeper: sin AICLIENT_TEAM_ID, el build queda firmado
# ad-hoc — perfecto para instalarlo en ESTE Mac, pero si le pasas el .dmg a
# otra persona/Mac, Gatekeeper lo bloqueará como "de un desarrollador no
# identificado" (la otra persona tendrá que hacer clic derecho > Abrir la
# primera vez). Para repartirlo sin esa fricción hace falta firmarlo con un
# Team ID de pago y notarizarlo con `xcrun notarytool` — eso no lo hace este
# script.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="AIclient"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$SCRIPT_DIR/build/DerivedData"
APP_NAME="AIclient"
APP_BUNDLE="$APP_NAME.app"
VOLUME_NAME="AIclient"
DIST_DIR="$SCRIPT_DIR/dist"
DMG_SOURCE_DIR="$SCRIPT_DIR/build/dmg-source"
ICNS_PATH="$SCRIPT_DIR/build/AIclient.icns"

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
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: falta create-dmg. Instálalo con: brew install create-dmg" >&2
  exit 1
fi
FILEICON_BIN="$(command -v fileicon || true)"
if [[ -z "$FILEICON_BIN" ]]; then
  echo "==> Aviso: 'fileicon' no está instalado (brew install fileicon) — el .dmg" \
       "se creará bien, pero el archivo .dmg en sí no llevará el icono" \
       "personalizado en el Finder (el volumen que se monta sí lo llevará, vía create-dmg)."
fi

# --- 1. limpiar artefactos previos -------------------------------------------
echo "==> Limpiando artefactos previos"
rm -rf "$DMG_SOURCE_DIR" "$ICNS_PATH"
mkdir -p "$DIST_DIR"

# --- 2. (re)generar el .xcodeproj a partir de project.yml --------------------
echo "==> xcodegen generate"
xcodegen generate

# --- 3. firma: automática con tu Team ID si lo defines; si no, ad-hoc --------
SIGNING_ARGS=()
if [[ -n "${AICLIENT_TEAM_ID:-}" ]]; then
  echo "==> Firmando con Team ID: $AICLIENT_TEAM_ID"
  SIGNING_ARGS+=(DEVELOPMENT_TEAM="$AICLIENT_TEAM_ID" CODE_SIGN_STYLE=Automatic)
else
  echo "==> AICLIENT_TEAM_ID no definido: firma ad-hoc (ver nota de Gatekeeper arriba)"
  SIGNING_ARGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
fi

# --- 4. build -----------------------------------------------------------------
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

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_BUNDLE"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: no se encontró $BUILT_APP tras el build." >&2
  exit 1
fi
echo "==> App compilada en: $BUILT_APP"

# --- 5. extraer el .icns que Xcode ya generó desde Assets.xcassets ----------
# Xcode compila AppIcon.appiconset a un .icns dentro del propio .app durante
# el build (nombre = ASSETCATALOG_COMPILER_APPICON_NAME, "AppIcon" en
# project.yml). Buscamos ese .icns en vez de asumir el nombre exacto.
echo "==> Extrayendo el icono de la app (.icns)..."
FOUND_ICNS="$(find "$BUILT_APP/Contents/Resources" -maxdepth 1 -name '*.icns' 2>/dev/null | head -n 1 || true)"
if [[ -n "$FOUND_ICNS" ]]; then
  cp "$FOUND_ICNS" "$ICNS_PATH"
  echo "    -> $(basename "$FOUND_ICNS") copiado a $(basename "$ICNS_PATH")"
else
  echo "==> Aviso: no se encontró ningún .icns compilado — el .dmg se hará sin icono personalizado."
fi

# --- 6. preparar la carpeta fuente del .dmg ----------------------------------
echo "==> Preparando carpeta fuente del .dmg"
mkdir -p "$DMG_SOURCE_DIR"
cp -R "$BUILT_APP" "$DMG_SOURCE_DIR/"

# --- 7. crear el .dmg con create-dmg -----------------------------------------
DMG_NAME="AIclient.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"
rm -f "$DIST_DIR"/rw.*."$DMG_NAME" 2>/dev/null || true

echo "==> Creando $DMG_NAME con create-dmg"
CREATE_DMG_ARGS=(
  --volname "$VOLUME_NAME"
  --window-size 500 300
  --icon-size 100
  --icon "$APP_BUNDLE" 125 150
  --app-drop-link 375 150
)
if [[ -f "$ICNS_PATH" ]]; then
  CREATE_DMG_ARGS+=(--volicon "$ICNS_PATH")
fi

# create-dmg puede devolver código de salida distinto de 0 en algunos casos
# (p. ej. si no logra aplicar el layout de ventana en un Mac sin sesión
# gráfica activa) aunque el .dmg final sí se haya creado bien — así que
# comprobamos el archivo resultante en vez de fiarnos solo del exit code.
set +e
create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$DMG_SOURCE_DIR/"
CREATE_DMG_STATUS=$?
set -e
if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: create-dmg no produjo $DMG_PATH (código de salida $CREATE_DMG_STATUS)." >&2
  exit 1
fi
if [[ "$CREATE_DMG_STATUS" != "0" ]]; then
  echo "==> Aviso: create-dmg terminó con código $CREATE_DMG_STATUS." \
       "El .dmg se creó, pero es posible que el paso de maquetación (AppleScript" \
       "vía Finder) no se haya podido completar — eso deja el .dmg 'crudo':" \
       "el .VolumeIcon.icns queda visible sin ocultar y el atajo a Applications" \
       "puede no quedar bien colocado (aunque normalmente sí está presente)." >&2
  echo "    Causa más común: falta darle permiso de Automatización a la app" \
       "desde la que corres este script (Terminal/iTerm) para controlar Finder:" \
       "Ajustes del Sistema > Privacidad y seguridad > Automatización." >&2
  echo "    Después de concederlo, vuelve a correr ./make-dmg.sh." >&2
fi

# --- 8. icono del propio archivo .dmg (el que ves en el Finder sin montar) --
if [[ -f "$ICNS_PATH" && -n "$FILEICON_BIN" ]]; then
  echo "==> Aplicando el icono al archivo $DMG_NAME"
  "$FILEICON_BIN" set "$DMG_PATH" "$ICNS_PATH"
fi

echo "==> Listo: $DMG_PATH"
open "$DIST_DIR"
