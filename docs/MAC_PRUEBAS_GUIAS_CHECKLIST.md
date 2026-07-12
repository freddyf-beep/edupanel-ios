# Relevo Mac — cierre de Pruebas y Guías

Este checklist es la continuación obligatoria del cierre hecho en Windows. No amplía
el alcance: Adaptaciones PIE con IA, Simulación de estudiantes, Calibración Bloom e
Historial/versiones siguen como **Próximamente**.

## 1. Preparar y compilar

1. Configurar `Config/Shared.xcconfig` y agregar `GoogleService-Info.plist` al target.
2. Abrir `EduPanel.xcodeproj` en Xcode y resolver paquetes.
3. Ejecutar `./scripts/build-simulator.sh`.
4. Corregir cualquier diagnóstico real de Swift/UIKit sin cambiar el contrato Firestore.
5. Ejecutar una compilación de dispositivo con `./scripts/build-device.sh`.

## 2. Matriz mínima de Pruebas

- Crear, editar, duplicar, eliminar y reabrir una prueba.
- Probar los 7 tipos: selección múltiple, V/F, pareados, ordenar, completar,
  respuesta corta y desarrollo.
- Subir/reemplazar/eliminar imágenes; guardar y comprobar que las referencias vigentes
  sobreviven y que solo se limpia el medio propio huérfano.
- Insertar desde el banco un ítem de Prueba y una actividad de Guía compatible.
- Generar contenido general con IA y revisar el borrador antes de guardar.
- Importar un `.docx` menor a 10 MB y corregir la alternativa marcada por defecto.
- Exportar DOCX, PDF alumno y PDF pauta; previsualizar, compartir e imprimir.
- Aplicar a estudiantes, corregir los 7 tipos, usar exigencia PIE, exportar CSV y
  sincronizar con Calificaciones.

## 3. Matriz mínima de Guías

- Crear, editar, duplicar, eliminar y reabrir una guía.
- Probar sus 13 actividades y los bloques texto/imagen/tabla/separador.
- Probar OA, unidad, recursos, imágenes de opciones y actividad de colorear.
- Insertar desde el banco una actividad de Guía y un ítem de Prueba compatible.
- Generar contenido general con IA y revisar antes de guardar.
- Exportar DOCX, PDF alumno y PDF pauta; previsualizar, compartir e imprimir.

## 4. Interoperabilidad y seguridad de datos

- Repetir en colegio principal y colegio secundario.
- Abrir el mismo documento en web e iOS; provocar una edición concurrente y confirmar
  que no se pisan campos conocidos ni futuros.
- Abrir documentos con tipos desconocidos y confirmar que quedan visibles/protegidos.
- Verificar que el banco usa `users/{uid}/itemBank` y que las evaluaciones respetan el
  scope del colegio activo.

## 5. Criterio final

El relevo termina cuando el Simulator y un iPhone real completan la matriz sin crash,
el PDF/DOCX abre correctamente y el IPA contiene `Payload/EduPanel.app/EduPanel`.
