# Prompt listo — continuar Asistencia Docente en EduPanel iOS

Copia y entrega al agente de `EduPanel_IOS` el texto siguiente:

---
Trabaja localmente en `/Users/freddy/Developer/EduPanel/edupanel_IOS` y desarrolla la primera versión nativa de **Asistencia Docente**. Esta tarea es solamente para el rol docente.

Antes de editar:

1. Lee completos `AGENTS.md`, `docs/PRODUCT_VISION.md` y `docs/WORKING_AGREEMENT.md`.
2. Lee completo el contrato implementado por la web en `/Users/freddy/Developer/EduPanel/edupanel_local/docs/ASISTENCIA_DOCENTE_WEB_IOS_HANDOFF.md`.
3. Ejecuta `git status --short --branch`, conserva todos los cambios existentes y revisa la arquitectura, navegación, modelos, repositorios Firebase, tests y scheme actuales.
4. Inspecciona, como fuente de verdad complementaria, estos archivos web:
   - `/Users/freddy/Developer/EduPanel/edupanel_local/lib/curriculo.ts`
   - `/Users/freddy/Developer/EduPanel/edupanel_local/lib/libro-clases-core.ts`
   - `/Users/freddy/Developer/EduPanel/edupanel_local/lib/libro-clases-report.ts`
   - `/Users/freddy/Developer/EduPanel/edupanel_local/lib/libro-clases-repository.ts`
   - `/Users/freddy/Developer/EduPanel/edupanel_local/components/edu-panel/libro-clases/libro-clases-shell.tsx`

## Resultado esperado

Implementa un flujo iPhone nativo para que el docente abra su clase/bloque actual, pase lista rápidamente, corrija excepciones, vea un resumen, guarde y firme con confianza. La web y iOS comparten Firestore, tipos y reglas de negocio, pero son polos opuestos en presentación: la web es densa, masiva, orientada a teclado/reportes; iOS debe ser simple, de una mano y centrada en la clase actual. **No copies la pantalla web ni uses una web view.**

## Alcance obligatorio

- Integrar el acceso en la navegación docente existente, preferentemente dentro del área/tab de clases vigente y sin crear un rol nuevo.
- Resolver curso, fecha y bloque actual desde los datos existentes; permitir cambiar bloque/fecha mediante controles nativos secundarios.
- Reutilizar exactamente los cuatro estados: `presente`, `ausente`, `atraso`, `retirado`.
- Una lista nueva debe iniciar visualmente “Sin confirmar”. Puede portar `presente` como valor provisional, pero no cuenta ni se puede firmar hasta que el docente confirme.
- Incluir una acción primaria inequívoca “Confirmar todos presentes”.
- Permitir cambiar excepciones de forma individual con áreas táctiles cómodas y lenguaje visible, no solo iconos crípticos.
- Incluir un modo rápido/avance por estudiantes adecuado a iPhone. Usa haptics discretos al marcar y al completar.
- Copiar estados del bloque anterior únicamente como borrador: `confirmado: false`, `metodo: copiado`, sin `marcadoAt`.
- Mostrar cantidad pendiente, resumen P/A/T/R y objetivo/actividad antes de firmar.
- Bloquear firma si falta objetivo, actividad o cualquier confirmación.
- Bloquear edición después de firmar. Reabrir exige confirmación y motivo breve, preserva firma anterior y agrega metadata de reapertura.
- Mostrar estados de carga, guardando, guardado, error y reintento. No ocultar un fallo de red.
- Implementar al menos una estrategia segura de guardado compatible con Firestore actual. Si agregas tolerancia offline, usa las capacidades estándar del SDK y deja claro qué se sincronizó; no inventes todavía una cola avanzada de resolución de conflictos.
- Leer y escribir las rutas schema v2 descritas en el handoff, tanto colegio `principal` como colegio secundario. No migrar a v3.
- Tratar legacy exactamente como el handoff: editable sin `confirmado` queda pendiente; firmado legacy sin `confirmado` se lee como confirmado.
- Mantener `metodo` y timestamps compatibles con web.
- Añadir pruebas unitarias del núcleo y del cálculo acumulado. Mantén la lógica de negocio fuera de las Views para que sea comprobable.

## UX nativa obligatoria

- Diseña primero para una mano y para la clase actual.
- Usa SwiftUI y componentes del sistema; no traduzcas el grid web a tarjetas pequeñas.
- Aplica divulgación progresiva: lista y acción primaria primero; fecha, bloque, reapertura y detalles en menus/sheets apropiados.
- Usa Liquid Glass de forma intencional en navegación, controles flotantes y sheets, nunca sacrificando lectura.
- Soporta Dynamic Type, VoiceOver, modo claro/oscuro, contraste y áreas táctiles mínimas adecuadas.
- Asegura que VoiceOver anuncie nombre, estado, si está confirmado y el resultado de la acción.
- No dependas solo del color para presente/ausente/atraso/retirado o para el guardado.
- Añade haptics para confirmación individual, finalización, firma y error, sin saturar.
- Mantén identidad visual y tono docente de EduPanel.

## Fuera de alcance

No implementes cuentas de estudiantes, apoderados, administración institucional, QR/cámara, NFC, GPS, biometría, SIGE directo, notificaciones a familias, participación de videoclase, analítica institucional, esquema v3 ni las “Ideas futuras · Asistencia” del Admin web. No amplíes la tarea a otros roles.

El registro por voz web existe, pero para este primer corte iOS prioriza el flujo manual completo. Solo impleméntalo si el endpoint, autenticación y permisos ya están listos y puedes conservar una revisión explícita antes de aplicar; de lo contrario, deja el modelo preparado y documenta la omisión.

## Forma de entrega

1. Implementa localmente y conserva cambios ajenos.
2. Compila el scheme real y ejecuta las pruebas relevantes.
3. Abre el simulador y recorre: clase actual → confirmar todos presentes → marcar una ausencia y un atraso → revisar/firma → reabrir con motivo → guardar y recargar.
4. Revisa al menos texto grande, VoiceOver, modo claro y oscuro.
5. Corrige los problemas encontrados antes de terminar.
6. Entrega un resumen conciso con archivos, decisiones, pruebas, simulador y limitaciones reales.

No crees rama, commit, push, pull request, IPA, GitHub Action ni TestFlight salvo autorización explícita de Freddy.

---
