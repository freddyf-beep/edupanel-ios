# Contrato API de EduPanel iOS

La app usa Firestore directamente para datos docentes y un backend Next/Vercel
para operaciones protegidas. La fuente de verdad del backend es el proyecto web
`edupanel_local`, que puede estar ubicado junto a este repositorio. No se deben
duplicar esos endpoints dentro del proyecto Xcode.

## Configuración

- Debug/Simulator: `Config/Debug.xcconfig` usa `http://127.0.0.1:3000`.
- Release/CI: `EDUPANEL_API_BASE_URL` debe ser una URL HTTPS explícita.
- Todas las rutas protegidas reciben `Authorization: Bearer <Firebase ID token>`.
- Las claves de Firebase Admin, Gemini/Vertex y QR pertenecen al servidor; nunca a la app.

## Rutas consumidas por iOS

- `GET /api/check-allowlist`
- `POST /api/redeem-invite`
- `POST /api/redeem-test-invite`
- `POST /api/generar-evaluacion`
- `POST /api/generar-clase`
- `POST /api/asistencia/qr/resolve`
- `POST /api/courses/{courseId}/preview-delete`
- `DELETE /api/courses/{courseId}`

El dictado actual no llama `/api/bitacora-por-voz`: Apple Speech produce texto y
el docente lo revisa antes de guardarlo en el leccionario. El endpoint web exige
audio y corresponde a una fase posterior de análisis estructurado.

La creación de clases con IA usa el motor integrado del backend con
`aiModelTier: luna` y `aiExperience: standard`; no envía claves ni selección de
proveedor desde el dispositivo. Requiere un usuario permitido con `ai_access`.
La respuesta se aplica como borrador local y solo se persiste cuando el docente
la revisa y pulsa **Guardar**.

## Validación del backend

Desde `edupanel_local`:

```bash
npm run typecheck
npm test -- --reporter=dot
npm run build
QA_BASE_URL=http://127.0.0.1:3000 node scripts/qa-smoke.mjs
```

Antes de producción se debe comprobar que todas las rutas anteriores estén
versionadas y desplegadas en el repositorio web. Un build verde de iOS no valida
por sí solo el despliegue de Vercel ni la presencia de sus secretos.
