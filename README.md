# AIclient (macOS) — Paso 1: estructura del proyecto y modelos base

Cliente de chat SwiftUI nativo de macOS para backends OpenAI-compatible
(Ollama, NVIDIA NIM, vLLM, llama.cpp) accesibles vía Tailscale.

> Proyecto solo macOS — sin target ni build de iOS.

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

## Siguiente paso

Paso 2: `Networking/` (cliente OpenAI-compatible con streaming SSE) +
`ViewModels/` + las vistas reales (lista de providers, chat). Dime cuándo
seguimos.
