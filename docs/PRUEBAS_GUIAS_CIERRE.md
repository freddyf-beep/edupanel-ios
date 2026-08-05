# Cierre focalizado: Pruebas y Guías en iOS

## Objetivo vigente

Cerrar los módulos nativos de **Pruebas** y **Guías** con interoperabilidad
Firestore/web, preservación de contenido futuro y una experiencia SwiftUI completa.
El proyecto debe quedar preparado para su compilación, prueba en Simulator y
validación en iPhone cuando el trabajo continúe desde un Mac.

## Fuera del cierre actual — Próximamente

Estas capacidades quedan deliberadamente fuera del alcance. No deben considerarse
un olvido ni bloquear el cierre actual:

1. Adaptaciones PIE mediante IA.
2. Simulación de estudiantes.
3. Calibración de Bloom.
4. Historial y versiones de Pruebas/Guías.

La app debe mostrarlas como **Próximamente**, sin navegaciones o acciones ficticias.

## Incluido en el cierre

> La lista siguiente describe el motor **legacy Firestore**. No debe
> interpretarse como soporte de edición o exportación para ExamForge.

### Pruebas

- Hub, detalle, CRUD, duplicación y editor de los siete tipos.
- Currículo/OA, estímulos, recursos e imágenes.
- Aplicación, corrección, notas PIE, resultados, CSV y Calificaciones.
- Banco de ítems compartido con Guías.
- Creación general mediante IA usando el endpoint web autenticado.
- Importación Word aproximada y revisable.
- Exportación para estudiante/con pauta, vista previa, compartir e imprimir.

### Guías

- Hub, detalle, CRUD, duplicación y editor de los trece tipos.
- Currículo/OA, bloques, recursos e imágenes.
- Banco de ítems compartido con Pruebas.
- Creación general mediante IA usando el endpoint web autenticado.
- Exportación para estudiante/con pauta, vista previa, compartir e imprimir.
- Manejo seguro de medios reemplazados o huérfanos, sin romper referencias web.

## Validación diferida al Mac

- Compilar con Xcode y resolver cualquier diagnóstico del SDK real.
- Ejecutar en Simulator y dispositivo.
- Probar Firebase principal/colegio secundario.
- Probar edición concurrente web/iOS y contenido futuro.
- Verificar PDF/DOCX, impresión, PhotosPicker y Firebase Storage.
- Confirmar el IPA y el flujo completo de navegación.

## Estado previo del cierre en Windows

Implementado en código y sincronizado con el proyecto Xcode:

- Editores nativos de 7 tipos de Pruebas y 13 tipos de actividades de Guías.
- Aplicación, corrección, resultados, CSV y sincronización con Calificaciones.
- Banco de ítems compartido con conversión entre tipos compatibles.
- Creación general con IA mediante `/api/generar-evaluacion` autenticado.
- Importación aproximada de `.docx` para Pruebas y exportación `.docx` para ambos módulos.
- PDF alumno/pauta, formato institucional, vista previa, compartir e impresión nativa.
- Limpieza post-guardado de medios propios reemplazados que ya no están referenciados.
- Las cuatro funciones excluidas aparecen como **Próximamente** y no navegan a flujos falsos.

La validación que originalmente quedó diferida en Windows se ejecutó después en
macOS; el estado vigente y las limitaciones reales se describen a continuación y
en `docs/UI_AUDIT_2026-08-03.md`.

## Actualización iOS — motor ExamForge

La app incorpora compatibilidad de lectura con el contrato vigente del backend:

- consulta disponibilidad y documentos con Firebase ID Token;
- separa pruebas y guías mediante el contexto de integración;
- filtra por curso, unidad, tipo, estado y búsqueda;
- abre el detalle en iPhone y representa encabezado, pie, texto enriquecido,
  secciones, numeración de preguntas, alternativas, justificación, rúbrica,
  imágenes autenticadas, separadores y espacios de respuesta;
- respeta curso, asignatura y unidad del contexto al filtrar;
- conserva una advertencia visible para bloques futuros no soportados;
- si el motor o la red no están disponibles, mantiene visibles los documentos
  legacy y ofrece reintento.

La edición y exportación ExamForge quedan deliberadamente pendientes porque el
motor aún está evolucionando. No se muestran como capacidades terminadas y no
bloquean la lectura de documentos ya creados.
