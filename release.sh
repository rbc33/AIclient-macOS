#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# release.sh — publica una versión de AIclient (Mac + iOS). NO hace commit de
# tus cambios: eso va antes, con tu propio `git commit` + `git push`.
#
#   0. comprueba que no hay nada sin commitear y que estás igual que GitHub
#   1. elige la versión (la siguiente a la última etiqueta vX.Y.Z) y la fija
#      en project.yml junto al nº de build
#   2. genera el .dmg (make-dmg.sh) y el .ipa sin firmar (build-ipa.sh, que
#      también actualiza apps.json, la fuente de SideStore)
#   3. sube project.yml y apps.json con un commit "Release AIclient X.Y.Z"
#      (SideStore lee apps.json de GitHub: sin esto no vería la versión nueva)
#   4. crea la release vX.Y.Z en GitHub con el .dmg y el .ipa
#   5. crea/actualiza el tap de Homebrew rbc33/homebrew-aiclient y su cask
#      (versión + sha256). La primera vez crea el repo del tap en GitHub.
#   6. instala/actualiza AIclient en este Mac con Homebrew
#
# Uso:
#   ./release.sh              # siguiente parche: 1.0.3 -> 1.0.4
#   ./release.sh --minor      # 1.0.3 -> 1.1.0
#   ./release.sh --major      # 1.4.2 -> 2.0.0
#   ./release.sh 0.1.0        # versión explícita
#   ./release.sh --replace    # rehace la ÚLTIMA versión publicada
#                             # (borra su release y su etiqueta)
#
# Si todavía no hay ninguna etiqueta, la primera versión es MARKETING_VERSION
# de project.yml (o la que le pases).
#
# Variables opcionales:
#   AICLIENT_REPO=usuario/repo          repo de la app      (def. rbc33/AIclient-macOS)
#   AICLIENT_TAP=usuario/homebrew-xxx   repo del tap        (def. rbc33/homebrew-aiclient)
#   AICLIENT_TAP_DIR=ruta               copia local del tap (def. ../homebrew-aiclient;
#                                       si no existe, se clona en una carpeta temporal)
#   AICLIENT_NO_INSTALL=1               no instalar/actualizar con brew en este Mac
#
# Requisitos: Xcode, XcodeGen, create-dmg (brew install xcodegen create-dmg)
# y GitHub CLI con sesión iniciada (brew install gh && gh auth login).
# El repo de la app tiene que ser público (SideStore y Homebrew descargan sin
# credenciales). Si el tap no existe todavía en GitHub, se crea solo.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION=""
REPLACE=""
BUMP="patch"
for arg in "$@"; do
  case "$arg" in
    --replace) REPLACE="--replace" ;;
    --minor)   BUMP="minor" ;;
    --major)   BUMP="major" ;;
    --*)       echo "error: opción desconocida '$arg' (--replace, --minor, --major)." >&2; exit 1 ;;
    *)
      if [[ -z "$VERSION" && "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        VERSION="$arg"
      else
        echo "error: argumento no válido: '$arg'." >&2
        echo "       release.sh ya no hace commit: haz antes 'git add -A && git commit -m ... && git push'." >&2
        exit 1
      fi
      ;;
  esac
done
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: este script solo puede correr en macOS." >&2
  exit 1
fi
for tool in gh git xcodegen xcodebuild create-dmg shasum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: falta '$tool' (ver requisitos arriba)." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "error: GitHub CLI sin sesión. Ejecuta: gh auth login" >&2; exit 1; }

# Un rebase a medias (p. ej. un `git pull --rebase` anterior que chocó con lo
# que había en GitHub) deja el repo sin rama: no se puede publicar así.
GIT_DIR_PATH="$(git rev-parse --git-dir)"
if [[ -d "$GIT_DIR_PATH/rebase-merge" || -d "$GIT_DIR_PATH/rebase-apply" ]]; then
  echo "error: hay un rebase a medias. Resuélvelo antes de publicar:" >&2
  echo "       git status            # para ver los archivos en conflicto" >&2
  echo "       git rebase --abort    # o para deshacerlo y volver a como estabas" >&2
  exit 1
fi

REPO="${AICLIENT_REPO:-rbc33/AIclient-macOS}"
TAP="${AICLIENT_TAP:-rbc33/homebrew-aiclient}"
TAP_DIR="${AICLIENT_TAP_DIR:-../homebrew-aiclient}"
TAP_OWNER="${TAP%%/*}"
TAP_SHORT="${TAP#*/homebrew-}"           # rbc33/homebrew-aiclient -> aiclient
BREW_CASK="$TAP_OWNER/$TAP_SHORT/aiclient" # nombre completo para brew install

# La etiqueta vX.Y.Z tiene que apuntar al código que llevan el .dmg y el
# .ipa: nada sin commitear, y tu main igual que el de GitHub.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: hay cambios sin commitear. Haz commit y push primero:" >&2
  git status --short >&2
  exit 1
fi
echo "==> Comprobando que estás igual que GitHub"
# FETCH_HEAD y no origin/main: así funciona aunque el remoto no tenga
# configurado el refspec que mantiene origin/main al día.
git fetch -q origin main
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse FETCH_HEAD)"
if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  if git merge-base --is-ancestor "$REMOTE_HEAD" "$LOCAL_HEAD"; then
    echo "error: tienes commits sin subir a GitHub. Haz 'git push origin main' primero." >&2
  else
    echo "error: GitHub tiene commits que no tienes aquí. Tráelos primero:" >&2
    echo "       git pull --rebase origin main" >&2
  fi
  exit 1
fi
git fetch -q --tags origin

# --- versión: la siguiente a la última etiqueta vX.Y.Z --------------------------
LAST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"
LAST_VERSION="${LAST_TAG#v}"
if [[ -z "$VERSION" ]]; then
  if [[ -z "$LAST_VERSION" ]]; then
    # Primera release: la versión que ya haya en project.yml.
    VERSION="$(sed -n -E 's/^ *MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' project.yml | head -n 1)"
    [[ -n "$VERSION" ]] || VERSION="1.0.0"
  elif [[ -n "$REPLACE" ]]; then
    VERSION="$LAST_VERSION"
  else
    IFS=. read -r MAJOR MINOR PATCH <<< "$LAST_VERSION"
    case "$BUMP" in
      major) VERSION="$((MAJOR + 1)).0.0" ;;
      minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
      *)     VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    esac
  fi
fi
TAG="v$VERSION"
DMG="dist/AIclient-$VERSION.dmg"
IPA_NAME="AIclient-$VERSION.ipa"
IPA="dist/$IPA_NAME"
echo "==> Versión a publicar: $VERSION${LAST_VERSION:+ (la anterior era $LAST_VERSION)}"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && [[ "$REPLACE" != "--replace" ]]; then
  echo "error: la release $TAG ya existe. Usa --replace para rehacerla." >&2
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
# Solo los archivos que genera este script (ya se comprobó arriba que no
# había nada más sin commitear).
ICON="AIclient/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png"
git add project.yml apps.json "$ICON"
if git diff --cached --quiet -- project.yml apps.json "$ICON"; then
  echo "==> project.yml y apps.json sin cambios"
else
  git commit -q -m "Release AIclient $VERSION" -- project.yml apps.json "$ICON"
fi
git push -q origin HEAD:main

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
