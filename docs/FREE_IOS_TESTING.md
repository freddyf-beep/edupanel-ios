# Prueba gratis en iPhone sin Mac ni Apple Developer pago

Esta ruta sirve para validar el primer hito de EduPanel iOS en un iPhone real sin usar TestFlight.

## Resumen

GitHub Actions compila la app en macOS y genera un `.ipa` sin firma. Luego ese `.ipa` se instala desde Windows usando una herramienta de sideloading como Sideloadly o AltStore.

## Limitaciones importantes

- No es TestFlight.
- Con Apple ID gratis, la app normalmente expira a los 7 dias y hay que reinstalar/refrescar.
- Conviene usar un Apple ID secundario para herramientas de sideloading.
- Si mas adelante quieres testers reales, estabilidad y distribucion limpia, sigue siendo necesario Apple Developer Program.

## Secrets necesarios en GitHub

Para el workflow gratis `Build unsigned iOS IPA` solo necesitas:

- `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- `EDUPANEL_API_BASE_URL`
- `GOOGLE_REVERSED_CLIENT_ID`

No necesitas todavia:

- Certificado `.p12`
- Provisioning profile `.mobileprovision`
- App Store Connect API key `.p8`
- Apple Developer Program pagado

## Preparar secrets desde Windows

Desde PowerShell, en la carpeta del repo:

```powershell
.\scripts\copy-secret-base64.ps1 -Path "C:\ruta\GoogleService-Info.plist"
```

El contenido base64 queda en el portapapeles. Pegalo en GitHub como secret `GOOGLE_SERVICE_INFO_PLIST_BASE64`.

Para `EDUPANEL_API_BASE_URL`, pega la URL HTTPS de Vercel, por ejemplo:

```txt
https://tu-app.vercel.app
```

Para `GOOGLE_REVERSED_CLIENT_ID`, usa el valor `REVERSED_CLIENT_ID` dentro de `GoogleService-Info.plist`, con forma parecida a:

```txt
com.googleusercontent.apps.xxxxxxxxx
```

## Ejecutar el workflow gratis

1. Sube los cambios al repo `freddyf-beep/edupanel-ios`.
2. En GitHub, entra al repo.
3. Ve a `Settings` -> `Secrets and variables` -> `Actions`.
4. Crea los 3 secrets indicados arriba.
5. Ve a `Actions`.
6. Abre `Build unsigned iOS IPA`.
7. Presiona `Run workflow`.
8. Espera que termine.
9. Descarga el artifact `EduPanel-unsigned-ipa`.
10. Descomprime el artifact si GitHub lo entrega como `.zip`.
11. Obtendras `EduPanel-unsigned.ipa`.

## Instalar en iPhone desde Windows

Opcion recomendada para primera prueba: Sideloadly.

1. Instala iTunes/iCloud desde Apple si la herramienta lo requiere.
2. Instala Sideloadly: https://sideloadly.io/
3. Conecta el iPhone por USB.
4. Confia en el computador desde el iPhone.
5. Arrastra `EduPanel-unsigned.ipa` a Sideloadly.
6. Ingresa tu Apple ID.
7. Instala.
8. En iPhone, si aparece bloqueo de desarrollador, ve a `Configuracion` -> `General` -> `VPN y gestion de dispositivos` y confia en el perfil.

Alternativa: AltStore.

- Guia oficial Windows: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows

## Cuando pasar a TestFlight

Pasa a TestFlight cuando:

- La app abre correctamente.
- Google Sign-In funciona.
- El dashboard carga horario real.
- El toggle de clase completada persiste en Firestore.
- Quieres probar con mas personas sin reinstalar cada 7 dias.
