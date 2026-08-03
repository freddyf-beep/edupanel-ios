# Dictado por voz — guion y registro de validación

Fecha técnica: 2026-07-21. Locale preferido: `es-CL`; fallback: `es-ES`.

## Guion fijo (60–90 segundos)

> Hoy, martes veintiuno de julio, trabajamos con quinto básico B en la asignatura de Matemática. El objetivo fue representar fracciones equivalentes usando material concreto y explicar el procedimiento con palabras propias. Al inicio revisamos la tarea anterior; después, cada grupo comparó un medio, dos cuartos y cuatro octavos. La mayoría identificó correctamente la equivalencia, aunque fue necesario reforzar la diferencia entre numerador y denominador. En el cierre, Camila explicó su estrategia frente al curso y usamos esa respuesta para corregir un error frecuente. Para la próxima clase conviene retomar la recta numérica, preparar apoyos visuales para estudiantes del PIE y reservar diez minutos para una salida breve. No se asignaron calificaciones ni diagnósticos; esta nota queda disponible para que el docente la revise, corrija, copie o elimine.

## Línea base del prototipo recibido

La revisión del código anterior mostró una única cadena de transcripción, reemplazo directo por cada resultado y término de la sesión al recibir un final. No había rotación controlada para sesiones largas, separación entre texto confirmado/parcial, protección de una corrección manual, fallback explícito ni manejo completo de interrupción/background. Esta es una línea base estructural; no es una medición acústica y no se le atribuye una tasa de precisión.

## Resultado verificable

- Pruebas automatizadas: parciales/finales sin duplicación exacta; edición preservada; reinicio tras final; límite de tres reinicios ante error persistente; detener/reanudar; permisos autorizado, denegado y restringido; recognizer ausente; fallback no on-device; cambio de ruta, interrupción, background y limpiar.
- Simulador: el modal abre, el texto es editable y los controles Guardar/Copiar/Limpiar son accesibles; cerrar detiene el servicio mediante `onDisappear`.
- Desde el detalle de una clase, el texto revisado se guarda únicamente al pulsar **Guardar** en `actividad` del bloque real del leccionario (`AttendanceBook`). El bloque usa el ID estable del horario y el mismo documento Firestore que el panel.
- Reapertura: se verificó en Simulator que el comentario guardado vuelve a aparecer al salir y abrir nuevamente la clase.
- Privacidad: no se guarda audio. La transcripción solo se persiste después de la confirmación docente; la pantalla informa si el procesamiento es on-device o si iOS puede usar el servicio de Apple.
- Compatibilidad: el endpoint web `/api/bitacora-por-voz` exige audio y devuelve objetivo/asistencia estructurados. El fallback iOS actual usa Apple Speech y guarda el texto revisado como actividad; no afirma realizar ese análisis de IA.

## Prueba acústica manual

Pendiente en un iPhone físico con micrófono y una persona que lea el guion completo. Debe registrarse literalmente el resultado y contar: omisiones, duplicaciones, errores en “Matemática”, “fracciones equivalentes”, “numerador”, “denominador”, “Camila”, “PIE”, además de la puntuación. No se declara una mejora de precisión acústica hasta completar esa prueba, porque depende del dispositivo, ruido y disponibilidad del servicio de Apple.

La validación acústica en un iPhone físico sigue pendiente. La integración de IA estructurada también queda pendiente hasta incorporar grabación temporal de audio, envío autenticado y una pantalla de revisión de objetivo/asistencia sin exponer claves privadas.
