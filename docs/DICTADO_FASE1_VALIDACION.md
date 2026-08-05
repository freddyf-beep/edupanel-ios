# Dictado por voz — guion y registro de validación

Fecha técnica: 2026-07-21. Locale preferido: `es-CL`; fallback: `es-ES`.

## Guion fijo (60–90 segundos)

> Hoy, martes veintiuno de julio, trabajamos con quinto básico B en la asignatura de Matemática. El objetivo fue representar fracciones equivalentes usando material concreto y explicar el procedimiento con palabras propias. Al inicio revisamos la tarea anterior; después, cada grupo comparó un medio, dos cuartos y cuatro octavos. La mayoría identificó correctamente la equivalencia, aunque fue necesario reforzar la diferencia entre numerador y denominador. En el cierre, Camila explicó su estrategia frente al curso y usamos esa respuesta para corregir un error frecuente. Para la próxima clase conviene retomar la recta numérica, preparar apoyos visuales para estudiantes del PIE y reservar diez minutos para una salida breve. No se asignaron calificaciones ni diagnósticos; esta nota queda disponible para que el docente la revise, corrija, copie o elimine.

## Línea base del prototipo recibido

La revisión del código anterior mostró una única cadena de transcripción, reemplazo directo por cada resultado y término de la sesión al recibir un final. No había rotación controlada para sesiones largas, separación entre texto confirmado/parcial, protección de una corrección manual, fallback explícito ni manejo completo de interrupción/background. Esta es una línea base estructural; no es una medición acústica y no se le atribuye una tasa de precisión.

## Resultado verificable

- Pruebas automatizadas: parciales/finales sin duplicación exacta; edición preservada; reinicio tras final; límite de tres reinicios ante error persistente; detener/reanudar; permisos autorizado, denegado y restringido; recognizer ausente; fallback no on-device; cambio de ruta, interrupción, background y limpiar.
- Simulador: el modal abre, el texto es editable y los controles Guardar/Copiar/Limpiar son accesibles; cerrar detiene el servicio mediante `onDisappear`.
- Desde el detalle de una clase, el texto revisado se guarda únicamente al pulsar **Guardar**. Se anexa como una nota nueva a `actividad` del bloque real (`AttendanceBook`) sin reemplazar comentarios anteriores. El bloque usa el ID estable del horario, conserva el UUID de la nota para reintentos idempotentes y escribe en el mismo documento Firestore que el panel.
- Reapertura: se verificó en Simulator que el comentario guardado vuelve a aparecer al salir y abrir nuevamente la clase.
- Privacidad: no se guarda audio. La transcripción se conserva localmente como
  borrador recuperable; solo se escribe en el leccionario remoto después de la
  confirmación docente. La pantalla informa si el procesamiento es on-device o
  si iOS puede usar el servicio de Apple.
- Compatibilidad: el endpoint web `/api/bitacora-por-voz` exige audio y devuelve objetivo/asistencia estructurados. El fallback iOS actual usa Apple Speech y guarda el texto revisado como actividad; no afirma realizar ese análisis de IA.

## Prueba acústica manual

Pendiente en un iPhone físico con micrófono y una persona que lea el guion completo. Debe registrarse literalmente el resultado y contar: omisiones, duplicaciones, errores en “Matemática”, “fracciones equivalentes”, “numerador”, “denominador”, “Camila”, “PIE”, además de la puntuación. No se declara una mejora de precisión acústica hasta completar esa prueba, porque depende del dispositivo, ruido y disponibilidad del servicio de Apple.

La validación acústica en un iPhone físico sigue pendiente. La integración de IA estructurada también queda pendiente hasta incorporar grabación temporal de audio, envío autenticado y una pantalla de revisión de objetivo/asistencia sin exponer claves privadas.

## Segunda pasada — 4 de agosto de 2026

- Inicio presenta **Dictado rápido** y **Dictado guiado** juntos y con la misma
  jerarquía. El rápido solicita permisos y comienza sin una pantalla previa.
- Ningún contexto es obligatorio. Sin clase activa, la nota se autoguarda en
  **Notas sin vincular** y puede reabrirse, editarse, eliminarse o vincularse
  cuando vuelvan los datos remotos.
- El modo guiado permite escoger un bloque real, observación general,
  individual o grupal, estudiantes y metadatos pedagógicos opcionales.
- La bandeja ofrece bloques efectivos desde 14 días antes hasta 14 días después.
  La selección usa fecha + ID del bloque y pasa por el resolver académico para
  respetar periodos y futuras vacaciones, suspensiones o excepciones.
- Los borradores se aíslan por UID, usan escritura atómica y protección de
  archivos de iOS. Cerrar, ir a background o fallar el guardado remoto conserva
  el texto; descartar o limpiar elimina el borrador correspondiente.
- EduPanel añade al vocabulario de reconocimiento solo curso, asignatura,
  unidad y tema. No agrega nombres, identificadores de estudiantes,
  observaciones PIE, resultados ni resumen como contexto estructurado. Apple sí
  puede procesar lo que la persona pronuncie cuando el reconocimiento no sea
  local, y la interfaz lo explica antes de guardar.
- El nivel visual del micrófono se limita a 12,5 actualizaciones por segundo
  para no publicar una tarea en MainActor por cada buffer de audio.

Verificación manual realizada en iPhone 16 Pro Simulator: permisos de Speech y
micrófono, inicio automático, pausa, edición, autoguardado, cierre, reapertura
desde la bandeja, selección de taller y estudiante. La suite integrada terminó
con 75 pruebas aprobadas, 0 fallos y 0 omisiones en la verificación local final.
Incluye identidad UUID + SHA-256, actualización de metadatos sin duplicar texto
y reidentificación atómica de una corrección conflictiva. La precisión acústica
y las interrupciones reales siguen requiriendo un iPhone físico.
