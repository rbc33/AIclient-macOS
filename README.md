# AIclient (macOS + iOS)

Cliente de chat SwiftUI nativo para backends OpenAI-compatible (Ollama,
NVIDIA NIM, vLLM, llama.cpp/llama-swap) accesibles vía Tailscale.

> Dos targets que comparten exactamente el mismo código: **AIclient** (macOS
> 14+) y **AIclient-iOS** (iPhone + iPad, iOS 17+). La versión iOS se
> instala con SideStore — ver
> [Versión iOS: instalar con SideStore](#versión-ios-instalar-con-sidestore).

## Por qué XcodeGen en vez de crear el proyecto a mano

El `.xcodeproj` de Xcode se genera a partir de `project.yml` con
[XcodeGen](https://github.com/yonaskolb/XcodeGen), en vez de crearlo con el
asistente de Xcode. Ventajas para este proyecto en concreto:

- **Reproducible**: `project.yml` se versiona en git; el `.xcodeproj`
  (binario/XML generado) no. Nada de conflictos de merge en el project file.
- **`build-mac.sh` (Paso 3)** invocará `xcodebuild` directamente sobre el
  proyecto generado — no depende de que abras Xcode primero.

## Requisitos previos (en tu Mac)

```bash
brew install xcodegen
```

Necesitas Xcode 15+ instalado (para el SDK de macOS 14).

## Generar y abrir el proyecto

```bash
cd AIclient
xcodegen generate
open AIclient.xcodeproj
```

Esto crea `AIclient.xcodeproj` con un único scheme, **AIclient**. Pulsa Run
(⌘R) — debería compilar y mostrar la pantalla placeholder desde el primer
momento.

### Firma de código

`project.yml` deja `DEVELOPMENT_TEAM` vacío. Dos opciones:

1. En Xcode: selecciona el target **AIclient** → **Signing & Capabilities**
   → elige tu Team. Xcode reescribe esto en el `.xcodeproj` generado (no en
   `project.yml`, así que se perderá si vuelves a correr `xcodegen
   generate` — en ese caso repite el paso).
2. O rellena `DEVELOPMENT_TEAM: "TU_TEAM_ID"` en `project.yml` (lo obtienes
   con `security find-identity -v -p codesigning` o en Xcode → Settings →
   Accounts → tu cuenta → "Team ID").

## Estructura de carpetas

```
AIclient/
├── project.yml                    ← spec de XcodeGen (1 target macOS)
├── README.md
├── .gitignore
└── AIclient/                      ← árbol de fuentes del target
    ├── App/
    │   └── AIclientApp.swift      ← @main, punto de entrada SwiftUI
    ├── Models/                    ← ✅ Paso 1 (este mensaje)
    │   ├── ProviderConfig.swift   ← proveedor: nombre, tipo, baseURL, modelo, hasAPIKey
    │   ├── ChatMessage.swift      ← mensaje: rol, contenido, adjuntos, streaming, tok/s
    │   ├── Conversation.swift     ← conversación: mensajes + contexto compactable
    │   └── Attachment.swift       ← adjunto: imagen/PDF/documento
    ├── Networking/                ← Paso siguiente: cliente OpenAI-compatible + SSE
    ├── ViewModels/                ← Paso siguiente: @Observable view models
    ├── Views/
    │   └── ContentView.swift      ← placeholder, para que compile ya
    ├── Persistence/               ← Paso siguiente: Keychain + UserDefaults stores
    └── Resources/
        ├── Assets.xcassets/       ← AppIcon.appiconset listo para el Paso 4 (aún sin PNGs)
        ├── Info.plist              ← permisos de micro/voz
        └── AIclient.entitlements   ← sandbox + red cliente + micro + selección de archivos
```

Las carpetas `Networking/`, `ViewModels/` y `Persistence/` llevan un
`_FolderNotes.swift` de marcador (solo comentarios) para que git las
trackee y aparezcan como grupo en Xcode; bórralo sin miedo cuando añadas
los archivos reales.

## Sobre los modelos (`Models/`)

Los tres modelos que pediste, más `Attachment` como tipo de apoyo:

- **`ProviderConfig`**: value type `Codable`. Guarda `hasAPIKey: Bool`, no
  la clave en sí — la clave real vivirá en Keychain (Paso de Persistence) y
  se busca por `id`. Incluye `chatCompletionsURL` calculada y datos de
  ejemplo (`.example`, `.examples`) para previews.
- **`ChatMessage`**: `role` (system/user/assistant), `content` mutable
  (para ir anexando tokens en streaming), `isStreaming`, `tokensPerSecond`
  y `tokenCount` para el indicador de velocidad.
- **`Conversation`**: `messages` + `compactedSummary` /
  `compactedMessageCount` para el contexto compactable — `effectiveMessages`
  calcula qué se envía realmente al backend (resumen + cola sin compactar).
- **`Attachment`**: bytes inline (`Data`) + `kind` (image/pdf/document) +
  `mimeType`, para que `Conversation` siga siendo `Codable` de una pieza sin
  un almacén de blobs aparte (nota en el propio archivo si esto se vuelve
  pesado en el futuro).

Todos son `struct`, `Identifiable`, `Codable`, `Hashable` — capa de datos
pura, sin lógica de red ni de UI, lista para que `@AppStorage`/UserDefaults
los serialice tal cual en el paso de Persistence. No dependen de AppKit ni
de nada específico de macOS, así que si algún día quisieras una versión
iOS no habría que tocarlos.

## Nota sobre Tailscale y red local

El entitlement `com.apple.security.network.client` (sandbox de macOS) ya
está activado, así que la app podrá salir a `http://…tailnet…ts.net:PUERTO`
sin más permisos. macOS no aplica App Transport Security tan estrictamente
como iOS para tráfico saliente de una app sandboxed con ese entitlement,
así que no debería hacer falta ninguna excepción adicional para hablar con
tus servidores por HTTP plano dentro de la tailnet.

## Compilar e instalar con `build.sh`

Con `xcodegen` ya instalado, desde la carpeta del proyecto:

```bash
./build.sh
```

Esto hace, en orden: `xcodegen generate` → `xcodebuild clean build`
(Release) → cierra la instancia de AIclient que esté corriendo (si hay
alguna) → borra la versión anterior en `/Applications/AIclient.app` →
copia la nueva → la abre.

Por defecto firma **ad-hoc** (`CODE_SIGN_IDENTITY="-"`), que basta para
correr la app en este mismo Mac sin cuenta de Apple Developer. Variables de
entorno opcionales:

```bash
# Firmar con tu Team ID real (Automatic signing) en vez de ad-hoc
AICLIENT_TEAM_ID=ABCDE12345 ./build.sh

# Build incremental, sin "clean" (más rápido en iteraciones seguidas)
AICLIENT_SKIP_CLEAN=1 ./build.sh

# No abrir la app automáticamente al terminar
AICLIENT_NO_OPEN=1 ./build.sh
```

Si `xcodebuild` falla por firma ("Signing for AIclient requires a
development team") aun sin haber puesto `AICLIENT_TEAM_ID`, revisa que no
hayas fijado un Team a mano en Xcode con `CODE_SIGN_STYLE: Automatic` — en
ese caso usa la variable de entorno con tu Team ID.

## Empaquetar un `.dmg` con `make-dmg.sh`

Requiere `create-dmg` (y opcionalmente `fileicon` para el icono del propio
archivo `.dmg`):

```bash
brew install create-dmg
brew install fileicon   # opcional
```

Para repartir la app (o simplemente tener un instalador de toda la vida en
vez de depender de `build.sh` copiando a `/Applications`):

```bash
./make-dmg.sh
```

Compila en Release igual que `build.sh`, y además arma un `.dmg` de
arrastrar-y-soltar con `create-dmg`: dentro va `AIclient.app` junto a un
atajo a `/Applications`, como el instalador de cualquier app de macOS
normal, con el icono de la propia app como icono del volumen montado. Lo
deja en `dist/AIclient-<versión>.dmg` y abre esa carpeta en el Finder al
terminar. Si tienes `fileicon` instalado, también le pone ese mismo icono
al archivo `.dmg` en sí (el que ves en el Finder antes de montarlo) — sin
`fileicon` el script avisa y sigue igual, solo que ese archivo se queda con
el icono genérico de disco.

Admite las mismas variables de entorno que `build.sh`
(`AICLIENT_TEAM_ID`, `AICLIENT_SKIP_CLEAN`).

**Sobre Gatekeeper**: sin `AICLIENT_TEAM_ID` la app queda firmada ad-hoc.
Eso es suficiente para instalarla en tu propio Mac desde el `.dmg`, pero si
le pasas el `.dmg` a otra persona/Mac, Gatekeeper la marcará como "de un
desarrollador no identificado" — la primera vez tendrán que hacer clic
derecho sobre la app → Abrir (en vez de doble clic normal). Para repartirla
sin esa fricción hace falta:

1. Un Team ID de pago en el Apple Developer Program.
2. Firmar con ese Team (`AICLIENT_TEAM_ID=... ./make-dmg.sh`).
3. Notarizarla con `xcrun notarytool submit` y "graparle" el ticket con
   `xcrun stapler staple` — eso no lo hace este script; si llegas a
   necesitarlo dime y lo añadimos.

## Versión iOS: instalar con SideStore

`project.yml` define un segundo target, **AIclient-iOS** (universal: iPhone
y iPad, iOS 17+), que compila las mismas fuentes que el de Mac. Lo que
cambia por plataforma está detrás de `#if os(macOS)` / `#if os(iOS)`, casi
todo en `AIclient/Views/PlatformCompat.swift`. Diferencias visibles en iOS:

- **Fotos** abre la fototeca del sistema (no el navegador de Archivos); las
  fotos se reducen a 2048 px y se mandan como JPEG.
- **Pegar** (imagen o texto del portapapeles) está dentro del menú **+**,
  porque en iPhone no cabe un botón más en la barra de escribir.
- Los botones de copiar/repetir y los tok/s de cada respuesta se ven
  siempre (en iPhone no hay "hover").
- El micrófono pide permiso la primera vez.

### 1. Compilar el `.ipa` y generar `apps.json`

```bash
./build-ipa.sh
```

Compila **sin firmar** (SideStore re-firma cada app con tu Apple ID al
instalarla, así que no hace falta cuenta de desarrollador de pago), deja el
resultado en `dist/AIclient.ipa` y escribe/actualiza `apps.json` en la raíz
del repo: la "fuente" que SideStore lee para saber qué versiones hay, dónde
descargarlas, su tamaño, el icono, los permisos, etc.

`apps.json` apunta a GitHub (el repo de `git remote origin`):

- el `.ipa` → asset de una **GitHub Release** con tag `v<versión>`
- `apps.json` y el icono → rama `main`, servidos por `raw.githubusercontent.com`

> El repo tiene que ser **público**: SideStore descarga sin credenciales.

### 2. Publicarlo

Con la CLI de GitHub (`brew install gh && gh auth login`), lo más cómodo es
que el propio script lo publique todo:

```bash
AICLIENT_PUBLISH=1 ./build-ipa.sh
```

Eso crea la release `v<versión>` con el `.ipa` adjunto y hace commit + push
de `apps.json` (y del icono). Si prefieres hacerlo a mano, el script te
imprime los comandos exactos al terminar.

### 3. Añadir la fuente en el iPhone

En SideStore: **Sources → +** y pega:

```
https://raw.githubusercontent.com/<usuario>/<repo>/main/apps.json
```

(el script te imprime la URL exacta). AIclient aparece en la fuente y se
instala desde ahí.

### Sacar una versión nueva

Sube `MARKETING_VERSION` en `project.yml` (por ejemplo `1.0.0` → `1.0.1`) y
vuelve a correr `AICLIENT_PUBLISH=1 ./build-ipa.sh`. La versión tiene que
cambiar para que SideStore la ofrezca como actualización; las anteriores se
conservan en `apps.json`. Variables opcionales del script:
`AICLIENT_RELEASE_NOTES` (por defecto, el último mensaje de commit),
`AICLIENT_GITHUB_REPO`, `AICLIENT_DEVELOPER_NAME`, `AICLIENT_SKIP_CLEAN=1`.

### Info.plist y entitlements

`AIclient/Resources/Info.plist` (Mac), `Info-iOS.plist` (iOS) y
`AIclient.entitlements` (Mac) están escritos a mano y enlazados con
`INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS`. Antes se generaban con las
claves `info:`/`entitlements:` de XcodeGen, que **reescriben esos archivos
en cada `xcodegen generate`** y borraban lo añadido a mano. Ambos plists
permiten HTTP plano (`NSAllowsArbitraryLoads`) para hablar con los
servidores de tu tailnet por `http://…ts.net`.

## Publicar una versión: `release.sh`

Todo de una vez, para Mac e iOS:

```bash
./release.sh 1.0.1
./release.sh 1.0.0 --replace   # rehacer una versión ya publicada
```

Hace, en orden: `./clean.sh` → fija `MARKETING_VERSION` (y el nº de build =
nº de commits) en `project.yml` → `make-dmg.sh` y `build-ipa.sh` (que
actualiza `apps.json`) → commit + push de `project.yml` y `apps.json` →
release `vX.Y.Z` en GitHub con `AIclient-X.Y.Z.dmg` y `AIclient-X.Y.Z.ipa` →
actualiza la cask del tap de Homebrew (versión + sha256 del `.dmg`) → instala
o actualiza AIclient en este Mac con `brew`.

- Necesita `gh auth login` y que el repo de la app sea **público**.
- Se niega a publicar si tienes cambios sin commitear (la etiqueta tiene que
  apuntar al código que lleva el `.dmg`/`.ipa`); `AICLIENT_ALLOW_DIRTY=1`
  para saltarte la comprobación.
- El tap es `rbc33/homebrew-aiclient` (`AICLIENT_TAP` para cambiarlo). Si no
  existe en GitHub, el script lo crea junto con `Casks/aiclient.rb`. Usa tu
  copia local en `../homebrew-aiclient` si la hay; si no, lo clona en una
  carpeta temporal.
- `AICLIENT_NO_INSTALL=1` para no tocar la app instalada en este Mac.

Una vez publicada:

```bash
brew install --cask rbc33/aiclient/aiclient   # instalar
brew upgrade --cask aiclient                  # actualizar
```

La app va firmada ad-hoc y sin notarizar, así que la cask le quita la
cuarentena al instalarla para que Gatekeeper no la bloquee.

`./clean.sh` borra `build/` y `dist/` (lo llama `release.sh` al empezar).

## Búsqueda web (opcional): instalar SearXNG

La app puede buscar en la web antes de responder (botón de globo en el chat),
pero ningún backend de chat (Ollama, vLLM, llama.cpp…) navega por sí mismo —
para eso la app necesita un buscador propio al que preguntarle. Usamos
[SearXNG](https://github.com/searxng/searxng), un meta-buscador open source
que te instalas tú (gratis, sin API key) y alcanzas por Tailscale igual que
tus proveedores de modelos.

Instrucciones para instalarlo con Docker Compose (el método oficial) en el
mismo servidor donde ya corres Ollama/vLLM/etc.:

```bash
# 1. Carpeta del proyecto + plantillas oficiales
mkdir -p ./searxng/core-config/
cd ./searxng/
curl -fsSL \
    -O https://raw.githubusercontent.com/searxng/searxng/master/container/docker-compose.yml \
    -O https://raw.githubusercontent.com/searxng/searxng/master/container/.env.example
cp .env.example .env

# 2. Config por defecto, para tenerla ANTES del primer arranque
curl -fsSL -o core-config/settings.yml \
    https://raw.githubusercontent.com/searxng/searxng/master/searx/settings.yml
```

Edita `core-config/settings.yml` y, bajo la clave `search:`, añade `json` a
`formats:` (por defecto solo trae `html` — sin este cambio, la app recibe un
HTTP 403 en cada búsqueda):

```yaml
search:
  formats:
    - html
    - json
```

Arranca los contenedores (levanta el propio SearXNG más un Valkey para
caché/límite de peticiones):

```bash
docker compose up -d
```

Por defecto queda escuchando en el puerto `8080` de esa máquina (cambiable
con `SEARXNG_PORT` en `.env` antes de arrancar). Compruébalo:

```bash
curl "http://localhost:8080/search?q=test&format=json"
```

Si el servidor tiene Tailscale corriendo (como para tus proveedores de
modelos), ya es alcanzable desde tu Mac en
`http://ese-servidor.tailnet-1234.ts.net:8080` sin abrir nada más — no hace
falta tocar `SEARXNG_HOSTNAME` ni ninguna config pensada para instancias
públicas. Pega esa URL en **Búsqueda web** dentro de AIclient (icono de
globo en la barra lateral) y pulsa "Probar búsqueda".

Si más adelante vuelves a tocar `core-config/settings.yml`, reinicia para
que cargue el cambio:

```bash
docker compose restart searxng
```

## Siguiente paso

Paso 2: `Networking/` (cliente OpenAI-compatible con streaming SSE) +
`ViewModels/` + las vistas reales (lista de providers, chat). Dime cuándo
seguimos.
