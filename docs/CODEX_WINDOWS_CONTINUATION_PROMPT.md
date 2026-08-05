# Prompt de continuidad para Codex en Windows

Copia el bloque siguiente en la primera tarea de Codex después de restaurar los
proyectos. Está escrito para impedir que un agente borre o normalice accidentalmente
los cambios locales preservados desde el Mac.

```text
Actúa como responsable técnico principal de EduPanel en este equipo Windows.

Rutas de trabajo esperadas:

- C:\Users\fredd\OneDrive\Documentos\edupanel_local
- C:\Users\fredd\OneDrive\Documentos\edupanel_IOS
- C:\Users\fredd\OneDrive\Documentos\Creador de Pruebas
- C:\Users\fredd\OneDrive\Documentos\edupanel_public

Este es un relevo desde Mac. Antes de modificar cualquier archivo:

1. Lee `03-Instrucciones\LEEME-PRIMERO.md` y valida `SHA256SUMS.txt` si todavía
   estás trabajando desde el paquete de migración.
2. En cada repositorio ejecuta `git status --short --branch`, `git log -1 --oneline`
   y `git remote -v`.
3. Lee por completo todos los `AGENTS.md` aplicables y la documentación señalada por
   ellos. En iOS lee además `docs/PRODUCT_VISION.md`, `docs/WORKING_AGREEMENT.md` y
   `docs/WINDOWS_HANDOFF.md`.
4. Conserva absolutamente todos los cambios locales existentes. No uses `git reset`,
   `git clean`, `checkout --`, normalizaciones masivas ni conversiones de fin de línea.
5. No crees commits, pushes, PR, despliegues o workflows remotos salvo que Freddy lo
   pida explícitamente para esa entrega.
6. Ejecuta `git config --global core.longpaths true`; estos proyectos contienen rutas
   que pueden superar 260 caracteres dentro de OneDrive.

Estado que debes verificar, no asumir ciegamente:

- `edupanel_IOS`: rama `codex/paridad-academica-ipa`; el último commit publicado es
  `595ef046b8886914ff97c4b775cbcb9864b1f778`. La build remota Xcode 26.6
  `30959173058` aprobó 75 tests. El paquete puede contener un commit posterior de
  cierre: usa Git como fuente de verdad.
- `edupanel_local`: rama `local/20260801-phase-8-examforge-integration`, HEAD base
  `46b389503a6c24c6c0a09de5b4fb988e33bf63bc`, cientos de cambios sin publicar y sin
  upstream. No cambies su rama ni su configuración `core.autocrlf` antes de revisar el
  diff.
- `edupanel_public`: rama `main`, HEAD base
  `75a184afd45ce7cb3bfa3345af612bc6e9ba9f08`, cientos de cambios locales preservados.
- `Creador de Pruebas`: todavía no tenía ningún commit; todos sus archivos son la única
  copia de trabajo. Usa Node 22+ y pnpm 11.9.0. Trátalo como datos irremplazables.

Reglas específicas de iOS desde Windows:

- Windows no puede ejecutar Xcode ni el Simulator oficial de iOS.
- Usa `scripts\windows-ci.ps1` para comprobar el entorno y, solo de forma explícita,
  ejecutar el smoke con Xcode 26 en GitHub Actions.
- No afirmes que una IPA sin firma es instalable. TestFlight sigue bloqueado hasta
  configurar certificado, provisioning profile, Apple Team y App Store Connect.
- La edición avanzada y exportación del motor nuevo de Pruebas/Guías se aplazó
  deliberadamente porque el motor aún no está terminado. No la conviertas en prioridad
  salvo nueva instrucción de Freddy.
- Dictado offline-first, borradores sin vincular, separación curso/taller y calendario
  académico ya tuvieron una segunda pasada. Verifica regresiones antes de reescribirlos.

Para `edupanel_local` y `edupanel_public`, instala dependencias desde sus
`package-lock.json`. Para `Creador de Pruebas`, usa Corepack/pnpm desde
`pnpm-lock.yaml`. Las carpetas `node_modules`, `.next`, `.turbo`, `dist`, builds de
Xcode y otras cachés se excluyeron intencionalmente del traslado porque se regeneran.

Después de la inspección, define un objetivo pequeño y explícito, prioriza P0/P1,
trabaja con autonomía y verifica proporcionalmente al riesgo. Si una tarea iOS necesita
compilación, súbela solo cuando Freddy autorice la fase remota y usa el smoke de Xcode
26 como comprobación final.
```
