# Dictado fase 1 — guion y registro de validación

Fecha técnica: 2026-07-21. Locale preferido: `es-CL`; fallback: `es-ES`.

## Guion fijo (60–90 segundos)

> Hoy, martes veintiuno de julio, trabajamos con quinto básico B en la asignatura de Matemática. El objetivo fue representar fracciones equivalentes usando material concreto y explicar el procedimiento con palabras propias. Al inicio revisamos la tarea anterior; después, cada grupo comparó un medio, dos cuartos y cuatro octavos. La mayoría identificó correctamente la equivalencia, aunque fue necesario reforzar la diferencia entre numerador y denominador. En el cierre, Camila explicó su estrategia frente al curso y usamos esa respuesta para corregir un error frecuente. Para la próxima clase conviene retomar la recta numérica, preparar apoyos visuales para estudiantes del PIE y reservar diez minutos para una salida breve. No se asignaron calificaciones ni diagnósticos; esta nota queda disponible para que el docente la revise, corrija, copie o elimine.

## Línea base del prototipo recibido

La revisión del código anterior mostró una única cadena de transcripción, reemplazo directo por cada resultado y término de la sesión al recibir un final. No había rotación controlada para sesiones largas, separación entre texto confirmado/parcial, protección de una corrección manual, fallback explícito ni manejo completo de interrupción/background. Esta es una línea base estructural; no es una medición acústica y no se le atribuye una tasa de precisión.

## Resultado posterior verificable

- Pruebas automatizadas: parciales/finales sin duplicación exacta; edición preservada; reinicio tras final; límite de tres reinicios ante error persistente; detener/reanudar; permisos autorizado, denegado y restringido; recognizer ausente; fallback no on-device; cambio de ruta, interrupción, background y limpiar.
- Simulador: modal abre, el texto es editable y los controles Copiar/Limpiar/Listo son accesibles; cerrar detiene el servicio mediante `onDisappear`.
- Privacidad: no hay escritura de audio o transcripción en Firestore, archivos, preferencias ni analytics. La pantalla informa si el procesamiento es on-device o si iOS puede usar el servicio de Apple.

## Prueba acústica manual

Pendiente en un iPhone físico con micrófono y una persona que lea el guion completo. Debe registrarse literalmente el resultado y contar: omisiones, duplicaciones, errores en “Matemática”, “fracciones equivalentes”, “numerador”, “denominador”, “Camila”, “PIE”, además de la puntuación. No se declara una mejora de precisión acústica hasta completar esa prueba, porque depende del dispositivo, ruido y disponibilidad del servicio de Apple.

La fase 1 termina en revisar, editar, copiar o eliminar. `ClassFeedbackDraft` queda solo como frontera de tipos local: no se persiste ni alimenta retroalimentación automática o personalización de planificaciones.
