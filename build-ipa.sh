#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# build-ipa.sh — compila la versión iOS/iPadOS de AIclient como .ipa SIN
# FIRMAR y actualiza apps.json, la "fuente" de SideStore que la anuncia.
#
# SideStore re-firma cada app con tu propio Apple ID al instalarla, así que
# el .ipa no necesita firma ni cuenta de desarrollador de pago.
#
# Uso:
#   ./build-ipa.sh                     # build + dist/AIclient.ipa + apps.json
#   AICLIENT_PUBLISH=1 ./build-ipa.sh  # además lo publica en GitHub (ver abajo)
#
# Variables opcionales:
#   AICLIENT_GITHUB_REPO=usuario/repo  # por defecto, el de `git remote origin`
#   AICLIENT_RELEASE_NOTES="..."       # por defecto, el último mensaje de commit
#   AICLIENT_DEVELOPER_NAME="..."      # por defecto, el usuario de GitHub
#   AICLIENT_SKIP_CLEAN=1              # build incremental (sin "clean")
#
# Dónde vive cada cosa (el repo de GitHub tiene que ser PÚBLICO, SideStore
# descarga sin credenciales):
#   - El .ipa se sube como asset de una GitHub Release con tag v<versión>.
#   - apps.json se versiona en la raíz del repo y SideStore lo lee de
#     https://raw.githubusercontent.com/<usuario>/<repo>/main/apps.json
#     — esa es la URL que añades en SideStore > Sources.
#
# Para sacar una versión nueva: sube MARKETING_VERSION en project.yml (tiene
# que cambiar para que SideStore la ofrezca como actualización) y vuelve a
# correr el script. Las versiones anteriores se conservan en apps.json.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="AIclient-iOS"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$SCRIPT_DIR/build/DerivedData-iOS"
APP_NAME="AIclient.app"
DIST_DIR="$SCRIPT_DIR/dist"
IPA_NAME="AIclient.ipa"
IPA_PATH="$DIST_DIR/$IPA_NAME"
SOURCE_JSON="$SCRIPT_DIR/apps.json"
ICON_REPO_PATH="AIclient/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png"

# --- 0. sanity checks --------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: este script solo puede correr en macOS." >&2
  exit 1
fi
for tool in xcodegen xcodebuild python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      xcodegen) echo "error: falta xcodegen. Instálalo con: brew install xcodegen" >&2 ;;
      *) echo "error: falta $tool (viene con Xcode / sus Command Line Tools)." >&2 ;;
    esac
    exit 1
  fi
done

# Repo de GitHub donde se publican el .ipa y apps.json.
GITHUB_REPO="${AICLIENT_GITHUB_REPO:-}"
if [[ -z "$GITHUB_REPO" ]]; then
  ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
  GITHUB_REPO="$(printf '%s' "$ORIGIN_URL" | sed -E -n 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' | sed -E 's#\.git$##')"
fi
if [[ -z "$GITHUB_REPO" ]]; then
  echo "error: no pude deducir el repo de GitHub de 'git remote origin'." >&2
  echo "       Pásalo a mano: AICLIENT_GITHUB_REPO=usuario/repo ./build-ipa.sh" >&2
  exit 1
fi
GITHUB_OWNER="${GITHUB_REPO%%/*}"
echo "==> Repo de GitHub: $GITHUB_REPO"

# --- 1. (re)generar el .xcodeproj --------------------------------------------
echo "==> xcodegen generate"
xcodegen generate

# --- 2. build sin firmar para dispositivos iOS -------------------------------
BUILD_ACTIONS=(build)
if [[ "${AICLIENT_SKIP_CLEAN:-0}" != "1" ]]; then
  BUILD_ACTIONS=(clean build)
fi

echo "==> xcodebuild ${BUILD_ACTIONS[*]} ($SCHEME, $CONFIGURATION, sin firmar)"
xcodebuild \
  -project "AIclient.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  "${BUILD_ACTIONS[@]}"

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: no se encontró $BUILT_APP tras el build." >&2
  exit 1
fi
echo "==> App compilada en: $BUILT_APP"

# --- 3. empaquetar el .ipa (un zip con Payload/AIclient.app) -----------------
mkdir -p "$DIST_DIR"
rm -f "$IPA_PATH"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/Payload"
cp -R "$BUILT_APP" "$WORK_DIR/Payload/"
(cd "$WORK_DIR" && zip -qry "$IPA_PATH" Payload)
echo "==> IPA: $IPA_PATH"

# --- 4. datos de la versión, sacados del propio .app -------------------------
PLIST="$BUILT_APP/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST" 2>/dev/null || echo "17.0")"
IPA_SIZE="$(stat -f%z "$IPA_PATH")"
RELEASE_DATE="$(date -u +%Y-%m-%d)"
TAG="v$VERSION"
RELEASE_NOTES="${AICLIENT_RELEASE_NOTES:-$(git log -1 --pretty=%s 2>/dev/null || echo "AIclient $VERSION")}"
DEVELOPER_NAME="${AICLIENT_DEVELOPER_NAME:-$GITHUB_OWNER}"

DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$IPA_NAME"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_REPO/main"
SOURCE_URL="$RAW_BASE/apps.json"
ICON_URL="$RAW_BASE/$ICON_REPO_PATH"

echo "==> Versión $VERSION ($BUILD_NUMBER), $BUNDLE_ID, iOS $MIN_OS+, $IPA_SIZE bytes"

# --- 5. escribir/actualizar apps.json (fuente de SideStore) ------------------
export SOURCE_JSON VERSION BUILD_NUMBER BUNDLE_ID MIN_OS IPA_SIZE RELEASE_DATE \
  RELEASE_NOTES DEVELOPER_NAME DOWNLOAD_URL SOURCE_URL ICON_URL
python3 - <<'PY'
import json, os

env = os.environ
path = env["SOURCE_JSON"]

try:
    with open(path, encoding="utf-8") as f:
        previous_versions = json.load(f)["apps"][0].get("versions", [])
except (FileNotFoundError, KeyError, IndexError, ValueError):
    previous_versions = []

new_version = {
    "version": env["VERSION"],
    "buildVersion": env["BUILD_NUMBER"],
    "date": env["RELEASE_DATE"],
    "localizedDescription": env["RELEASE_NOTES"],
    "downloadURL": env["DOWNLOAD_URL"],
    "size": int(env["IPA_SIZE"]),
    "minOSVersion": env["MIN_OS"],
}
# SideStore treats the FIRST entry as the latest release, so the new one
# goes on top; rebuilding the same version just replaces its entry.
versions = [new_version] + [v for v in previous_versions if v.get("version") != env["VERSION"]]

app = {
    "name": "AIclient",
    "bundleIdentifier": env["BUNDLE_ID"],
    "developerName": env["DEVELOPER_NAME"],
    "subtitle": "Chat con tus propios modelos de IA vía Tailscale.",
    "localizedDescription": (
        "Cliente de chat para tus propios servidores de modelos compatibles con la API "
        "de OpenAI (Ollama, llama.cpp/llama-swap, vLLM, NVIDIA NIM), alcanzables por "
        "Tailscale.\n\n"
        "• Varios proveedores y selector de proveedor + modelo en el propio chat\n"
        "• Respuestas en streaming con indicador de tokens/segundo\n"
        "• Fotos y archivos adjuntos (las imágenes se envían a modelos con visión)\n"
        "• Notas de audio grabadas desde el micrófono\n"
        "• Búsqueda web opcional con tu propia instancia de SearXNG\n"
        "• Claves API guardadas en el Llavero"
    ),
    "iconURL": env["ICON_URL"],
    "tintColor": "#7b2fff",
    "category": "utilities",
    "screenshotURLs": [],
    "permissions": [
        {"type": "network", "usageDescription": "Se conecta a tus servidores de modelos y a SearXNG en tu red local o tu tailnet."},
        {"type": "microphone", "usageDescription": "Graba notas de audio que adjuntas a tus mensajes."},
        {"type": "photos", "usageDescription": "Adjunta fotos de tu fototeca a los mensajes (selector del sistema, sin acceso a toda la fototeca)."},
    ],
    "versions": versions,
    # Legacy single-version fields, mirrored from versions[0] for older
    # SideStore/AltStore builds that predate the versions[] array.
    "version": versions[0]["version"],
    "versionDate": versions[0]["date"],
    "versionDescription": versions[0]["localizedDescription"],
    "downloadURL": versions[0]["downloadURL"],
    "size": versions[0]["size"],
}

source = {
    "name": "AIclient",
    # Never change this once people have added the source (SideStore keys
    # sources by it).
    "identifier": "com.ricardobenthem.aiclient.source",
    "sourceURL": env["SOURCE_URL"],
    "apps": [app],
    "news": [],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"==> apps.json actualizado ({len(versions)} versión/es)")
PY

# --- 6. (opcional) publicar en GitHub ----------------------------------------
if [[ "${AICLIENT_PUBLISH:-0}" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: AICLIENT_PUBLISH=1 necesita la CLI de GitHub: brew install gh && gh auth login" >&2
    exit 1
  fi
  echo "==> Publicando $IPA_NAME en la release $TAG de $GITHUB_REPO"
  if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$IPA_PATH" --repo "$GITHUB_REPO" --clobber
  else
    gh release create "$TAG" "$IPA_PATH" --repo "$GITHUB_REPO" \
      --title "AIclient $VERSION" --notes "$RELEASE_NOTES"
  fi

  echo "==> Subiendo apps.json e icono a main"
  git add apps.json "$ICON_REPO_PATH"
  if git diff --cached --quiet; then
    echo "    (apps.json sin cambios)"
  else
    git commit -m "SideStore: AIclient $VERSION"
  fi
  git push origin HEAD:main
fi

echo
echo "==> Listo."
echo "    IPA:          $IPA_PATH"
echo "    Fuente:       $SOURCE_JSON"
echo "    URL fuente:   $SOURCE_URL"
if [[ "${AICLIENT_PUBLISH:-0}" != "1" ]]; then
  echo
  echo "    Para publicarlo (o vuelve a correr con AICLIENT_PUBLISH=1):"
  echo "      gh release create $TAG \"$IPA_PATH\" --repo $GITHUB_REPO --title \"AIclient $VERSION\" --notes \"$RELEASE_NOTES\""
  echo "      git add apps.json \"$ICON_REPO_PATH\" && git commit -m \"SideStore: AIclient $VERSION\" && git push"
fi
echo
echo "    En el iPhone: SideStore > Sources > + > $SOURCE_URL"
