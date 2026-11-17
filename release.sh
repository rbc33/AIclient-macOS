#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# release.sh — publica una versión de AIclient (Mac + iOS):
#   ·  hace commit de tus cambios con el mensaje que le pases, se trae lo que
#      haya nuevo en GitHub (git pull --rebase)
#   0. limpia builds anteriores (clean.sh)
#   1. fija la versión en project.yml (MARKETING_VERSION y nº de build)
#   2. genera el .dmg (make-dmg.sh) y el .ipa sin firmar (build-ipa.sh, que
#      también actualiza apps.json, la fuente de SideStore)
#   3. hace commit de project.yml y apps.json y push de todo
#   4. crea la release vX.Y.Z en GitHub con el .dmg y el .ipa
#   5. crea/actualiza la cask del tap de Homebrew (versión + sha256) y la sube
#   6. instala/actualiza AIclient en este Mac con Homebrew
#
# Uso:
#   ./release.sh "Mensaje del commit"              # siguiente versión de parche (1.0.0 -> 1.0.1)
#   ./release.sh "Mensaje del commit" --minor      # 1.0.3 -> 1.1.0
#   ./release.sh "Mensaje del commit" --major      # 1.4.2 -> 2.0.0
#   ./release.sh 0.1.0 "Mensaje del commit"        # versión explícita
#   ./release.sh "Mensaje del commit" --replace    # rehace la ÚLTIMA versión publicada
#                                                  # (borra su release y su etiqueta)
#   ./release.sh                                   # si no hay cambios sin commitear
#
# La versión la lleva el script: mira la etiqueta vX.Y.Z más alta del repo y
# publica la siguiente. Si todavía no hay ninguna, usa MARKETING_VERSION de
# project.yml (o la que le pases explícitamente).
#
# El mensaje es para el commit de tus cambios (todo lo que haya sin commitear,
# p. ej. lo que acaba de copiar ./update-client.sh). Si hay cambios y no pasas
# mensaje, el script se para antes de compilar nada.
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
MESSAGE=""
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
      elif [[ -z "$MESSAGE" ]]; then
        MESSAGE="$arg"
      else
        echo "error: argumento de más: '$arg'. Pon el mensaje del commit entre comillas." >&2
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

# Commit de tus cambios. La etiqueta vX.Y.Z tiene que apuntar al código que
# llevan el .dmg y el .ipa, así que no se compila nada con cambios sueltos.
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ -z "$MESSAGE" ]]; then
    echo "error: hay cambios sin commitear. Pasa el mensaje del commit:" >&2
    echo "       ./release.sh \"mensaje\"" >&2
    git status --short >&2
    exit 1
  fi
  git add -A
  git commit -q -m "$MESSAGE"
  echo "==> Commit: ${MESSAGE%%$'\n'*}"
elif [[ -n "$MESSAGE" ]]; then
  echo "==> No hay cambios sin commitear: se ignora el mensaje"
fi

# Traer lo que haya en GitHub y no esté aquí (p. ej. un cambio hecho desde la
# web u otro Mac), y las etiquetas de versión. Si no, el push del paso 3 se
# rechaza ("non-fast-forward") después de haber compilado todo.
echo "==> Sincronizando con origin/main"
if ! git pull -q --rebase origin main; then
  echo >&2
  echo "error: lo que hay en GitHub choca con tus commits locales (conflicto)." >&2
  echo "       Mira los archivos con 'git status', o deshaz el intento con" >&2
  echo "       'git rebase --abort' (tus commits siguen ahí)." >&2
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
