# Prompt listo — implementar Asistencia QR en EduPanel iOS

Copia y entrega al agente que trabajará en `/Users/freddy/Developer/EduPanel/edupanel_IOS` el texto siguiente:

---

Trabaja localmente en `/Users/freddy/Developer/EduPanel/edupanel_IOS` y añade el **escáner QR de Asistencia Docente** sobre la asistencia nativa que ya está implementada. Esta tarea es exclusivamente para el rol docente.

## Lecturas obligatorias antes de editar

Lee completos, en este orden:

1. `/Users/freddy/Developer/EduPanel/edupanel_IOS/AGENTS.md`
2. `/Users/freddy/Developer/EduPanel/edupanel_IOS/docs/PRODUCT_VISION.md`
3. `/Users/freddy/Developer/EduPanel/edupanel_IOS/docs/WORKING_AGREEMENT.md`
4. `/Users/freddy/Developer/EduPanel/edupanel_local/docs/ASISTENCIA_QR_WEB_IOS_HANDOFF.md`
5. `/Users/freddy/Developer/EduPanel/edupanel_local/docs/ASISTENCIA_DOCENTE_WEB_IOS_HANDOFF.md`

Después ejecuta `git status --short --branch`, conserva todos los cambios locales y revisa, como mínimo:

- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/Models/AttendanceModels.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/Models/AttendanceRules.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/Services/AttendanceRepository.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/ViewModels/AttendanceViewModel.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/Views/Attendance/AttendanceView.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanel/Views/Attendance/AttendanceSheets.swift`
- `/Users/freddy/Developer/EduPanel/edupanel_IOS/EduPanelTests/AttendanceRulesTests.swift`
- el cliente HTTP/Firebase Auth existente que adjunta el ID token a las API web.

El handoff QR web–iOS es la fuente de verdad para payload, endpoints, errores, seguridad y reglas. No inventes otro esquema, otra firma ni acceso directo desde iOS a `attendance_qr_credentials`.

## Resultado esperado

Conserva toda la asistencia iOS actual y añade una acción visible `Escanear QR` para que el docente escanee tarjetas individuales con la cámara. Un QR se resuelve online por la API web y, solo después de una respuesta válida, confirma al estudiante presente con método `.qr` en el bloque activo.

Web e iOS son polos complementarios: la web administra e imprime las tarjetas; el iPhone solo escanea, valida y ejecuta el registro dentro de una experiencia nativa de una mano. No copies la UI web, no uses WebView y no añadas administración de credenciales a iOS.

## Contrato obligatorio

- Extiende `AttendanceMethod` con `case qr` usando raw value exacto `"qr"`.
- Envía `POST /api/asistencia/qr/resolve` con Firebase Bearer token y JSON:

```json
{
  "payload": "epatt:v1:...",
  "schoolId": "principal",
  "yearId": "2026",
  "course": "1° A"
}
```

- Decodifica `studentId`, `studentName` y `credentialId`.
- No analices ni confíes localmente en los segmentos del payload. No guardes secreto HMAC.
- No escribas asistencia dentro de `resolve`: la API solo resuelve. Aplica en el ViewModel existente:
  - `estado: presente`
  - `confirmado: true`
  - `metodo: qr`
  - `marcadoAt: ahora en ISO 8601`
- El `studentId` debe existir también en el bloque activo antes de cualquier cambio.
- QR solo confirma presencia. Ausencia, atraso y retiro continúan siendo acciones docentes manuales.
- La función requiere internet; sin red no cambies nada y ofrece lista/mode rápido existentes.

## Reglas de aplicación

1. Si el bloque está firmado, no iniciar o no aplicar escaneo y explicar por qué.
2. Si el estudiante ya está presente y confirmado, ignorar el duplicado sin guardar otra vez; mantener feedback discreto.
3. Si está ausente, atrasado o retirado y confirmado, pausar y presentar `¿Cambiar a presente?`, nombrando el estado anterior. Solo aplicar si el docente confirma.
4. Si está pendiente o presente sin confirmar, marcar presente inmediatamente con `.qr`.
5. Si `resolve` responde QR inválido, ajeno, revocado, rotado, de otro curso/año, estudiante fuera de nómina, rate limit, sesión vencida o error servidor, no modificar asistencia.
6. Tras un éxito, mostrar nombre, confirmación visual y haptic; luego reanudar el scanner.

## Escáner nativo

Usa `VisionKit.DataScannerViewController` limitado a `.barcode(symbologies: [.qr])`, siguiendo documentación oficial de Apple: https://developer.apple.com/documentation/visionkit/scanning-data-with-the-camera

Implementa:

- permiso de cámara con una descripción clara para el docente;
- comprobación de `DataScannerViewController.isSupported` e `isAvailable`;
- wrapper SwiftUI y protocolo de scanner inyectable;
- pausa inmediata al reconocer un código para evitar ráfagas y duplicados;
- cancelación segura al cerrar la pantalla;
- progreso de asistencia, últimos estudiantes leídos y botón `Finalizar`;
- acceso visible al modo rápido existente;
- estados claros para permiso no determinado, denegado, restringido, cámara ocupada/no disponible, dispositivo incompatible, sin red, validando, éxito y error reintentable;
- VoiceOver, Dynamic Type, contraste, modo claro/oscuro y áreas táctiles cómodas;
- Liquid Glass intencional en navegación y controles flotantes, sin reducir la lectura de cámara o mensajes.

No muestres payloads crudos ni los envíes a logs, analytics, crash reports o UserDefaults. Si necesitas deduplicación temporal, conserva solo un hash efímero en memoria o el `credentialId` devuelto tras una resolución válida.

## API y errores

Implementa un DTO de error que lea `error` y `code`. Trata específicamente:

- `400 INVALID_PAYLOAD`: QR no válido;
- `401`: renovar sesión o pedir reingreso;
- `403 CREDENTIAL_FORBIDDEN`: QR ajeno;
- `403 CREDENTIAL_REVOKED`: tarjeta revocada;
- `409 STALE_CREDENTIAL`: tarjeta anterior a una rotación;
- `409 SCOPE_MISMATCH`: otro curso/año;
- `409 STUDENT_NOT_IN_ROSTER`: estudiante fuera de nómina;
- `429 RATE_LIMITED`: pausar y respetar `Retry-After`;
- `503 CONFIGURATION_ERROR` o `RATE_LIMIT_UNAVAILABLE`: servicio temporalmente no disponible;
- pérdida de red/timeout: no modificar y permitir usar modo rápido.

Reutiliza el cliente HTTP existente que adjunta Firebase ID token. No crees una autenticación paralela.

## Pruebas y verificación obligatoria

Mantén lógica de resolución/aplicación fuera de las Views y agrega pruebas para:

- scan válido sobre pendiente;
- duplicado presente confirmado;
- ausencia, atraso y retiro confirmados que requieren autorización;
- bloque firmado;
- estudiante resuelto que no existe en el bloque activo;
- QR inválido, revocado, rotado y de otro curso;
- offline y timeout;
- cámara denegada;
- dispositivo no compatible;
- pausa/reanudación que evita procesar dos lecturas simultáneas;
- `AttendanceRepository` conserva `metodo: "qr"` al codificar y decodificar.

En simulador usa un scanner inyectado con payloads de prueba y recorre el flujo completo. Compila el scheme real, ejecuta tests y revisa visualmente texto grande, VoiceOver, claro/oscuro y tamaños de iPhone. La cámara real no puede darse por verificada en simulador: deja explícitamente pendiente una prueba en iPhone con tarjeta impresa y no declares la función completamente terminada hasta realizarla.

## Límites

- No modifiques la web desde esta tarea.
- No agregues cuentas/roles de estudiantes, autoservicio QR, administración de tarjetas, modo QR offline, NFC, GPS, biometría, apoderados, SIGE ni schema v3.
- No reemplaces ni regresiones el modo manual, masivo, rápido, firma, reapertura o reportes ya implementados.
- No crees rama, commit, push, PR, IPA, GitHub Action ni TestFlight sin autorización explícita de Freddy.

Al terminar, entrega archivos cambiados, decisiones, pruebas, recorrido de simulador, accesibilidad y la limitación concreta de cámara física.

---
