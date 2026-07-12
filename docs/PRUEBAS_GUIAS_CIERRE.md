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

## Estado del cierre en Windows

Implementado en código y sincronizado con el proyecto Xcode:

- Editores nativos de 7 tipos de Pruebas y 13 tipos de actividades de Guías.
- Aplicación, corrección, resultados, CSV y sincronización con Calificaciones.
- Banco de ítems compartido con conversión entre tipos compatibles.
- Creación general con IA mediante `/api/generar-evaluacion` autenticado.
- Importación aproximada de `.docx` para Pruebas y exportación `.docx` para ambos módulos.
- PDF alumno/pauta, formato institucional, vista previa, compartir e impresión nativa.
- Limpieza post-guardado de medios propios reemplazados que ya no están referenciados.
- Las cuatro funciones excluidas aparecen como **Próximamente** y no navegan a flujos falsos.

La compilación y la prueba de SDK real quedan conscientemente diferidas porque este
entorno Windows no dispone de Swift, Xcode ni Simulator. La secuencia exacta está en
`docs/MAC_PRUEBAS_GUIAS_CHECKLIST.md`.
