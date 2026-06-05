# EduPanel iOS

App iOS nativa en SwiftUI para replicar gradualmente la experiencia docente de EduPanel.

## Estado

- App: EduPanel
- Bundle id: `cl.edupanel.app`
- Plataforma minima: iOS 17
- UI inicial: login + dashboard docente "Hoy + resumen"
- Datos: Firebase Auth/Firestore + APIs Next/Vercel con Firebase ID Token

## Configuracion requerida

Antes de compilar en Xcode:

1. Crea una app iOS en Firebase con bundle id `cl.edupanel.app`.
2. Descarga `GoogleService-Info.plist`.
3. Agrega ese archivo a `EduPanel/Resources/` con target membership `EduPanel`.
4. Edita `Config/Shared.xcconfig`:
   - `EDUPANEL_API_BASE_URL`: URL HTTPS de Vercel, por ejemplo `https:/$()/tu-app.vercel.app`.
   - `GOOGLE_REVERSED_CLIENT_ID`: valor `REVERSED_CLIENT_ID` del `GoogleService-Info.plist`.

`GoogleService-Info.plist` queda ignorado por git para evitar subir credenciales de cliente.

## Desarrollo en Windows

Puedes editar todo el codigo SwiftUI desde Windows. Para compilar, firmar e instalar en un iPhone real sigue siendo necesario Xcode/macOS o un servicio cloud con macOS. No existe un Simulator iOS oficial local para Windows.

## Pruebas en iPhone real

Cuando tengas acceso a Xcode en Mac o a un runner macOS:

1. Abre `EduPanel.xcodeproj`.
2. Revisa `Config/Shared.xcconfig` y configura `DEVELOPMENT_TEAM`.
3. Agrega `GoogleService-Info.plist` al target `EduPanel`.
4. Conecta el iPhone, selecciona el dispositivo fisico y ejecuta el scheme `EduPanel`.

Para distribucion a otros telefonos, usa TestFlight o un flujo cloud que genere un `.ipa` firmado.

## GitHub Actions + TestFlight

El workflow `.github/workflows/testflight.yml` permite compilar en macOS, firmar, exportar `.ipa` y subir a TestFlight desde GitHub Actions.

Importante: esta carpeta `edupanel_IOS` debe estar subida a un repositorio de GitHub para que el workflow aparezca en la pestaña Actions. Puede ser un repo separado del proyecto web.

## Prueba gratis sin Apple Developer pago

Para validar el primer hito en un iPhone real sin Mac y sin pagar Apple Developer todavia, usa el workflow `.github/workflows/unsigned-ipa.yml`.

Ese workflow genera un `.ipa` sin firma para instalarlo manualmente con Sideloadly o AltStore desde Windows. Requiere solo estos secrets:

- `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- `EDUPANEL_API_BASE_URL`
- `GOOGLE_REVERSED_CLIENT_ID`

Guia paso a paso: `docs/FREE_IOS_TESTING.md`.

Requisitos fuera del repo:

1. Cuenta Apple Developer activa.
2. App creada en App Store Connect con bundle id `cl.edupanel.app`.
3. App iOS creada en Firebase con el mismo bundle id.
4. Certificado Apple Distribution exportado como `.p12`.
5. Provisioning Profile tipo App Store / App Store Connect para `cl.edupanel.app`.
6. App Store Connect API Key descargada como `.p8`.

Secrets requeridos en GitHub:

- `APPLE_TEAM_ID`: Team ID de Apple Developer.
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`: `.p12` convertido a base64.
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`: password usado al exportar el `.p12`.
- `IOS_PROVISIONING_PROFILE_BASE64`: `.mobileprovision` convertido a base64.
- `IOS_PROVISIONING_PROFILE_NAME`: nombre del provisioning profile, no el UUID.
- `KEYCHAIN_PASSWORD`: password temporal para el keychain del runner.
- `APP_STORE_CONNECT_API_KEY_ID`: Key ID de App Store Connect.
- `APP_STORE_CONNECT_API_ISSUER_ID`: Issuer ID de App Store Connect.
- `APP_STORE_CONNECT_API_KEY_BASE64`: archivo `.p8` convertido a base64.
- `GOOGLE_SERVICE_INFO_PLIST_BASE64`: `GoogleService-Info.plist` convertido a base64.
- `EDUPANEL_API_BASE_URL`: URL HTTPS del backend Vercel.
- `GOOGLE_REVERSED_CLIENT_ID`: `REVERSED_CLIENT_ID` del plist de Firebase.

Comandos utiles para convertir archivos a base64 en macOS:

```bash
base64 -i distribution.p12 | pbcopy
base64 -i EduPanel_AppStore.mobileprovision | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
base64 -i GoogleService-Info.plist | pbcopy
```

Luego ejecuta el workflow manualmente desde GitHub Actions: `Build iOS and Upload to TestFlight`.

## Flujo recomendado en Mac online

Desde el Mac online:

```bash
cd /ruta/a/edupanel_IOS
chmod +x scripts/*.sh
./scripts/mac-bootstrap.sh
```

Para compilar en Simulator:

```bash
./scripts/build-simulator.sh
```

Si el Mac online tiene otro modelo de Simulator, puedes pasar el destino completo:

```bash
./scripts/build-simulator.sh "platform=iOS Simulator,name=iPhone 15"
```

Para validar build de dispositivo fisico:

```bash
./scripts/build-device.sh
```

Para instalar y ejecutar en tu iPhone, lo mas directo sigue siendo abrir `EduPanel.xcodeproj` en Xcode, seleccionar tu iPhone conectado y presionar Run. Para un Mac online sin USB fisico, usa TestFlight o un servicio que permita firmar/exportar `.ipa`.

## Prueba visual con serve-sim

`serve-sim` requiere macOS, Xcode command line tools (`xcrun simctl`) y Node.js 18+. Cuando tengas un Mac o un Mac remoto:

```bash
cd /ruta/a/edupanel_IOS
./scripts/serve-sim.sh <SIMULATOR_UDID>
```

El script imprime una URL local para ver e interactuar con el Simulator desde el navegador.
