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
- `GET /api/examforge/access`
- `GET /api/examforge/v1/exams`
- `GET /api/examforge/v1/exams/{examId}`
- `GET /api/examforge/v1/assets/{assetId}`

Las rutas ExamForge se consumen en modo **solo lectura** y, cuando corresponde,
incluyen `x-edupanel-school-id`. iOS muestra listados, detalle y assets
autenticados sin reconstruir ni escribir el documento. La edición y la
exportación de este motor nuevo no se consideran terminadas y no forman parte
de esta integración; los flujos legacy continúan disponibles por separado.

Los assets autenticados tienen un requisito adicional de aislamiento: la ruta
del backend no debe responder con `Cache-Control: public, immutable`; antes de
producción debe usar caché privada o `no-store`. iOS fuerza recarga sin caché,
particiona su caché de imágenes por usuario/colegio, limita la descarga a 12 MB
y reduce imágenes grandes antes de decodificarlas. Esto protege al cliente,
pero no reemplaza la corrección del encabezado HTTP en el despliegue web.

El dictado actual no llama `/api/bitacora-por-voz`: Apple Speech produce texto y
la app lo autoguarda primero en `Application Support/EduPanel/VoiceNotes`. Cada
cuenta usa un archivo separado por un hash de su UID, con protección de archivos
de iOS; no se conserva audio. El docente puede mantener la nota sin contexto,
editarla y vincularla después al bloque real del leccionario. Un fallo de red no
elimina el borrador local.

Cada nota usa un UUID. Al vincularla, el bloque guarda ese UUID en
`notasVozIds` junto con una huella de contenido y metadatos pedagógicos mínimos;
así un reintento idéntico es idempotente y una corrección conflictiva no se
descarta silenciosamente. `observationScope` y los IDs de estudiantes se
persisten como relación estructurada en el mismo ámbito autenticado del
leccionario; los nombres solo se presentan al docente y no se agregan como
contexto de reconocimiento.

El endpoint web exige audio y corresponde a una fase posterior de análisis
estructurado. No debe conectarse desde iOS hasta aplicar el mismo filtro de
privacidad que el resto de la IA: no enviar nombres, identificadores de
estudiantes ni antecedentes PIE al modelo; validar tamaño/MIME; y evitar guardar
prompt o transcripción sensible en logs. La app tampoco debe incorporar una
clave de IA para suplir ese endpoint.

La creación de clases con IA usa el motor integrado del backend con
`aiModelTier: luna` y `aiExperience: standard`; no envía claves ni selección de
proveedor desde el dispositivo. Requiere un usuario permitido con `ai_access`.
La respuesta se aplica como borrador local y solo se persiste cuando el docente
la revisa y pulsa **Guardar**.

## Cursos, talleres y calendario

El espacio académico se identifica por `courseID`; `kind` distingue `curso` de
`taller`, mientras `dataKey` y `aliasKeys` mantienen compatibilidad con nombres
anteriores. iOS resuelve primero el ID y rechaza aliases ambiguos. No se agrega
un endpoint paralelo para este contrato: la lectura/configuración vigente sigue
en Firestore y las eliminaciones protegidas usan `/api/courses/{courseId}`.

El horario es recurrencia, no una lista de clases materializadas. La app ya
incluye un resolver local de periodos y excepciones, pero no existe una
colección/API de calendario académico verificada. Por eso esta entrega no inventa
CRUD ni importación remota. El contrato pendiente, zona horaria y política de
conflictos quedan definidos en `docs/ACADEMIC_CALENDAR_CONTRACT.md`.

El editor/exportador del motor nuevo de pruebas, guías y materiales continúa
fuera de alcance hasta que sus contratos del backend sean estables. iOS mantiene
lectura autenticada y no publica escritura especulativa.

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
