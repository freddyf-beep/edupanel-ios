# Relevo de EduPanel iOS: Mac a Windows

Este documento deja reproducible el trabajo diario desde Windows. El código se puede
editar, revisar y subir desde Windows; la compilación, los tests de iOS, Simulator y
la firma siguen ejecutándose en un runner macOS mediante GitHub Actions.

## Estado comprobado antes del relevo

- Repositorio: `freddyf-beep/edupanel-ios`.
- Rama de trabajo: `codex/paridad-academica-ipa`.
- Último commit publicado: `595ef046b8886914ff97c4b775cbcb9864b1f778`.
- CI validada: `iOS 26 smoke test`, ejecución `30959173058`.
- Runner validado: Xcode 26.6, build 17F113, Simulator iPhone 17 Pro con iOS 26.
- Resultado validado: build, instalación, lanzamiento y 75 tests correctos.
- Mac de origen: Xcode 16.2; no contiene identidades de firma ni perfiles de
  aprovisionamiento que deban exportarse.

La ejecución validada puede consultarse en:

<https://github.com/freddyf-beep/edupanel-ios/actions/runs/30959173058>

## Qué sí y qué no permite Windows

Windows permite:

- editar Swift, SwiftUI, documentación, workflows y scripts;
- trabajar con Git y GitHub CLI;
- iniciar y observar builds/tests de Xcode 26 en GitHub Actions;
- descargar y verificar artefactos de CI.

Windows no permite localmente:

- ejecutar Xcode o el Simulator oficial de iOS;
- validar visualmente una vista SwiftUI en Preview/Simulator;
- archivar o firmar una app Apple con herramientas locales de Xcode.

Por eso, antes de fusionar cambios Swift, la comprobación mínima desde Windows es el
workflow `iOS 26 smoke test`.

## Preparar el equipo Windows

Instala Git, GitHub CLI y un editor. Después, en PowerShell:

```powershell
gh auth login -h github.com -s repo,workflow
gh auth setup-git

git clone https://github.com/freddyf-beep/edupanel-ios.git edupanel_IOS
Set-Location .\edupanel_IOS
git switch --track origin/codex/paridad-academica-ipa
git config --global core.longpaths true
```

Comprueba el entorno sin iniciar ninguna build remota:

```powershell
.\scripts\windows-ci.ps1
```

El comando valida Git, GitHub CLI, autenticación, repositorio, rama y workflows. También
comprueba el único secret que usa el smoke y los tres que usa la IPA sin firma. Nunca
lee ni imprime sus valores.

## Compilar y probar con Xcode 26 desde Windows

El inicio de una ejecución siempre es explícito:

```powershell
.\scripts\windows-ci.ps1 -Smoke
```

El script exige un worktree limpio y que `HEAD` coincida con `origin/<rama>`. Después
inicia el workflow, encuentra su run, muestra el enlace y espera su resultado. Si falla,
hay que leer sus logs y corregir la causa real antes de volver a ejecutarlo.

Para usar otra rama:

```powershell
.\scripts\windows-ci.ps1 -Smoke -Branch codex/otra-rama
```

## Generar una IPA de inspección sin firma

```powershell
.\scripts\windows-ci.ps1 -Unsigned -Configuration Release -RetentionDays 14
```

Al terminar, el script muestra el identificador del run. Descarga y valida el artifact:

```powershell
.\scripts\windows-ci.ps1 -DownloadRun <run-id>
```

La descarga queda en `artifacts\<run-id>` y se compara con su SHA-256. `artifacts/`
está ignorado por Git.

Esta IPA es un binario de dispositivo **sin firma**. No es instalable directamente en
un iPhone. Sideloadly o AltStore tendrán que volver a firmarla para un dispositivo; una
distribución normal requiere TestFlight o firma Apple válida.

## Secrets ya preparados

La build y la IPA sin firma ya disponen en GitHub de:

- `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- `EDUPANEL_API_BASE_URL`
- `GOOGLE_REVERSED_CLIENT_ID`

`EduPanel/Resources/GoogleService-Info.plist` está ignorado por Git. No se debe
commitear. El runner lo reconstruye desde el primer secret, de modo que no hace falta
tenerlo en Windows para usar CI. Conviene conservar una copia privada para preparar
otro Mac o reemplazar la configuración Firebase en el futuro.

El helper para renovar un secret binario desde Windows es:

```powershell
.\scripts\copy-secret-base64.ps1 -Path "C:\ruta\GoogleService-Info.plist"
```

Solo copia el base64 al portapapeles; no lo guarda en el repositorio.

## TestFlight: preparado en código, bloqueado por credenciales

El workflow existe, pero no debe ejecutarse todavía. Este Mac no tenía certificados ni
perfiles instalados y GitHub no tiene los materiales Apple requeridos:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `IOS_PROVISIONING_PROFILE_NAME`
- `KEYCHAIN_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

Cuando exista una membresía Apple Developer y una app configurada en App Store
Connect, estos materiales deben generarse desde Apple, guardarse como GitHub Secrets y
conservarse en un gestor de secretos. Nunca deben entrar al repositorio ni guardarse sin
cifrado en el PC.

## Archivos locales que no viajan con `git clone`

Al preparar este relevo se detectaron dos archivos del proyecto iOS que Git no copia:

- `axe-video-2026-08-04T03:36:48Z.mp4`, 78.035.485 bytes, SHA-256
  `4b446a8a20fc292c211022a379e49b819fd7c3a01a25fa9e5822d28dfb0db441`.
- `EduPanel/Resources/GoogleService-Info.plist`, 1.208 bytes, SHA-256
  `03b7759b1e4c4d1066e17f3337d3c5b8f59e381096f205286c81d834feecc185`.

El video es evidencia local y no pertenece al repositorio. Debe copiarse explícitamente
si se quiere conservar. El plist debe moverse solo por un canal privado.

También existen cambios no publicados en los repositorios hermanos `edupanel_local` y
`edupanel_public`. No están protegidos por el push del proyecto iOS: deben restaurarse
desde el paquete de relevo preparado en el Mac o respaldarse por separado antes de
borrar el equipo.

## Regla de cierre para cada cambio Swift desde Windows

1. Revisar `git status` y conservar cambios ajenos.
2. Hacer cambios pequeños y coherentes.
3. Revisar `git diff --check` y el diff completo.
4. Subir la rama.
5. Ejecutar `windows-ci.ps1 -Smoke`.
6. Confirmar build, tests y screenshot de Simulator en el artifact.
7. No afirmar que existe una IPA instalable si solo se generó la IPA sin firma.

Para iniciar una nueva tarea de Codex sin perder el contexto del relevo, usa el prompt
preparado en [`CODEX_WINDOWS_CONTINUATION_PROMPT.md`](CODEX_WINDOWS_CONTINUATION_PROMPT.md).
