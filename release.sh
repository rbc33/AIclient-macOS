#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# release.sh — publica una versión de AIclient (Mac + iOS):
#   0. limpia builds anteriores (clean.sh)
#   1. fija la versión en project.yml (MARKETING_VERSION y nº de build)
#   2. genera el .dmg (make-dmg.sh) y el .ipa sin firmar (build-ipa.sh, que
#      también actualiza apps.json, la fuente de SideStore)
#   3. hace commit + push de project.yml y apps.json
#   4. crea la release vX.Y.Z en GitHub con el .dmg y el .ipa
#   5. crea/actualiza la cask del tap de Homebrew (versión + sha256) y la sube
#   6. instala/actualiza AIclient en este Mac con Homebrew
#
# Uso:
#   ./release.sh 1.0.1
#   ./release.sh 1.0.0 --replace   # rehace una versión ya publicada (borra
#                                  # su release y su etiqueta y la vuelve a crear)
#
# Variables opcionales:
#   AICLIENT_REPO=usuario/repo          repo de la app      (def. rbc33/AIclient-macOS)
#   AICLIENT_TAP=usuario/homebrew-xxx   repo del tap        (def. rbc33/homebrew-aiclient)
#   AICLIENT_TAP_DIR=ruta               copia local del tap (def. ../homebrew-aiclient;
#                                       si no existe, se clona en una carpeta temporal)
#   AICLIENT_NO_INSTALL=1               no instalar/actualizar con brew en este Mac
#   AICLIENT_ALLOW_DIRTY=1              publicar aunque haya cambios sin commitear
#
# Requisitos: Xcode, XcodeGen, create-dmg (brew install xcodegen create-dmg)
# y GitHub CLI con sesión iniciada (brew install gh && gh auth login).
# El repo de la app tiene que ser público (SideStore y Homebrew descargan sin
# credenciales). Si el tap no existe todavía en GitHub, se crea solo.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-}"
REPLACE="${2:-}"
if [[ -z "$VERSION" ]]; then
  echo "Uso: ./release.sh <versión> [--replace]   (p. ej. ./release.sh 1.0.1)" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: la versión tiene que ser X.Y.Z (p. ej. 1.0.1), no '$VERSION'." >&2
  exit 1
fi
if [[ -n "$REPLACE" && "$REPLACE" != "--replace" ]]; then
  echo "error: segundo argumento desconocido '$REPLACE' (solo se admite --replace)." >&2
  exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: este script solo puede correr en macOS." >&2
  exit 1
fi
for tool in gh git xcodegen xcodebuild create-dmg shasum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: falta '$tool' (ver requisitos arriba)." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "error: GitHub CLI sin sesión. Ejecuta: gh auth login" >&2; exit 1; }

REPO="${AICLIENT_REPO:-rbc33/AIclient-macOS}"
TAP="${AICLIENT_TAP:-rbc33/homebrew-aiclient}"
TAP_DIR="${AICLIENT_TAP_DIR:-../homebrew-aiclient}"
TAP_OWNER="${TAP%%/*}"
TAP_SHORT="${TAP#*/homebrew-}"           # rbc33/homebrew-aiclient -> aiclient
BREW_CASK="$TAP_OWNER/$TAP_SHORT/aiclient" # nombre completo para brew install
TAG="v$VERSION"

DMG="dist/AIclient-$VERSION.dmg"
IPA_NAME="AIclient-$VERSION.ipa"
IPA="dist/$IPA_NAME"

# La etiqueta vX.Y.Z apunta al commit que se sube en el paso 3: si hay cambios
# sin commitear, el .dmg/.ipa llevarían código que no está en ese commit.
DIRTY="$(git status --porcelain --untracked-files=no | grep -v -E ' (project\.yml|apps\.json)$' || true)"
if [[ -n "$DIRTY" && -z "${AICLIENT_ALLOW_DIRTY:-}" ]]; then
  echo "error: hay cambios sin commitear (haz commit primero, o AICLIENT_ALLOW_DIRTY=1):" >&2
  echo "$DIRTY" >&2
  exit 1
fi

# Traer lo que haya en GitHub y no esté aquí (p. ej. un cambio hecho desde la
# web u otro Mac). Si no, el push del paso 3 se rechaza ("non-fast-forward")
# después de haber compilado todo.
echo "==> Sincronizando con origin/main"
git pull -q --rebase --autostash origin main

# Comprobar ANTES de compilar nada si la release ya existe.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && [[ "$REPLACE" != "--replace" ]]; then
  echo "error: la release $TAG ya existe. Usa ./release.sh $VERSION --replace para rehacerla." >&2
  exit 1
fi

# --- 0. empezar limpio --------------------------------------------------------
./clean.sh

# --- 1. versión y número de build (nº de commits) -----------------------------
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> Versión $VERSION (build $BUILD)"
sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml

# --- 2. DMG (Mac) e IPA (iOS) -------------------------------------------------
AICLIENT_NO_OPEN=1 ./make-dmg.sh
[[ -f dist/AIclient.dmg ]] || { echo "error: make-dmg.sh no generó dist/AIclient.dmg" >&2; exit 1; }
mv dist/AIclient.dmg "$DMG"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "==> DMG: $DMG (sha256 $SHA)"

# build-ipa.sh también escribe apps.json apuntando a $TAG/$IPA_NAME.
AICLIENT_IPA_NAME="$IPA_NAME" AICLIENT_GITHUB_REPO="$REPO" AICLIENT_PUBLISH=0 ./build-ipa.sh
[[ -f "$IPA" ]] || { echo "error: build-ipa.sh no generó $IPA" >&2; exit 1; }

# --- 3. commit + push de la versión y la fuente de SideStore -----------------
# Solo estos archivos: cualquier otro cambio tuyo sin commitear se queda como está.
ICON="AIclient/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png"
git add project.yml apps.json "$ICON"
if git diff --cached --quiet -- project.yml apps.json "$ICON"; then
  echo "==> project.yml y apps.json sin cambios"
else
  git commit -q -m "Release AIclient $VERSION" -- project.yml apps.json "$ICON"
fi
git push -q origin HEAD

# --- 4. release en GitHub -----------------------------------------------------
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "==> Sustituyendo la release $TAG existente…"
  gh release delete "$TAG" --repo "$REPO" --yes --cleanup-tag
  git tag -d "$TAG" >/dev/null 2>&1 || true
fi
gh release create "$TAG" "$DMG" "$IPA" \
  --repo "$REPO" \
  --target "$(git rev-parse HEAD)" \
  --title "AIclient $VERSION" \
  --generate-notes

# --- 5. cask del tap de Homebrew ----------------------------------------------
TMP=""
cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

if [[ -d "$TAP_DIR/.git" ]]; then
  git -C "$TAP_DIR" pull -q --rebase || true
else
  if ! gh repo view "$TAP" >/dev/null 2>&1; then
    echo "==> Creando el tap $TAP en GitHub"
    gh repo create "$TAP" --public --description "Homebrew tap for AIclient"
  fi
  TMP="$(mktemp -d)"
  gh repo clone "$TAP" "$TMP/tap" -- --quiet
  TAP_DIR="$TMP/tap"
fi

CASK="$TAP_DIR/Casks/aiclient.rb"
if [[ -f "$CASK" ]]; then
  sed -i '' -E "s/^  version \"[^\"]*\"/  version \"$VERSION\"/" "$CASK"
  sed -i '' -E "s/^  sha256 .*/  sha256 \"$SHA\"/" "$CASK"
else
  echo "==> Creando la cask $CASK"
  mkdir -p "$(dirname "$CASK")"
  cat > "$CASK" <<EOF
cask "aiclient" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/AIclient-#{version}.dmg"
  name "AIclient"
  desc "Chat client for self-hosted OpenAI-compatible model servers"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :sonoma"

  app "AIclient.app"

  # La app va firmada ad-hoc y sin notarizar: sin quitar la cuarentena,
  # Gatekeeper no deja abrirla.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/AIclient.app"]
  end

  zap trash: "~/Library/Preferences/com.ricardobenthem.aiclient.plist"
end
EOF
fi

# Un tap recién creado está vacío y sin rama: la fijamos a main.
git -C "$TAP_DIR" checkout -q -B main 2>/dev/null || true
git -C "$TAP_DIR" add Casks/aiclient.rb
if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "==> La cask ya estaba en $VERSION"
else
  git -C "$TAP_DIR" commit -q -m "aiclient $VERSION"
fi
git -C "$TAP_DIR" push -q -u origin main

# Fuera archivos intermedios; en dist/ quedan solo el .dmg y el .ipa.
rm -rf build

# --- 6. instalar/actualizar AIclient en este Mac con Homebrew ----------------
# `yes |` responde «sí» a las preguntas de brew. Con pipefail, `yes` muere por
# SIGPIPE al terminar brew y la tubería daría error aunque brew haya ido bien:
# por eso aquí cuenta solo el código de salida de brew.
brew_yes() {
  local status
  set +o pipefail
  yes | brew "$@"
  status=$?
  set -o pipefail
  return "$status"
}

if [[ -z "${AICLIENT_NO_INSTALL:-}" ]] && command -v brew >/dev/null 2>&1; then
  echo
  echo "==> Actualizando AIclient en este Mac con Homebrew…"
  brew update --quiet || true
  BREW_FAILED=""
  if brew list --cask aiclient >/dev/null 2>&1; then
    if [[ "$REPLACE" == "--replace" ]]; then
      # Misma versión: `upgrade` no la ve como nueva.
      brew_yes reinstall --cask "$BREW_CASK" || BREW_FAILED=1
    else
      brew_yes upgrade --cask "$BREW_CASK" || BREW_FAILED=1
    fi
  else
    brew_yes install --cask "$BREW_CASK" || BREW_FAILED=1
  fi
  # Típico la primera vez: ya hay un /Applications/AIclient.app instalado con
  # build.sh (o borraste la app a mano y brew no puede desinstalar la vieja).
  # --force sobrescribe lo que haya y la instala de cero.
  if [[ -n "$BREW_FAILED" ]]; then
    echo "==> Reinstalando AIclient desde cero…"
    brew uninstall --cask --force aiclient >/dev/null 2>&1 || true
    brew_yes install --cask --force "$BREW_CASK" \
      || echo "aviso: no se pudo instalar con Homebrew. La release está publicada igualmente."
  fi
fi

echo
echo "==> AIclient $VERSION publicada"
echo "    Release:     https://github.com/$REPO/releases/tag/$TAG"
echo "    Homebrew:    brew install --cask $BREW_CASK"
echo "    Actualizar:  brew upgrade --cask aiclient"
echo "    SideStore:   https://raw.githubusercontent.com/$REPO/main/apps.json"
