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

## Siguiente paso

Paso 2: `Networking/` (cliente OpenAI-compatible con streaming SSE) +
`ViewModels/` + las vistas reales (lista de providers, chat). Dime cuándo
seguimos.
