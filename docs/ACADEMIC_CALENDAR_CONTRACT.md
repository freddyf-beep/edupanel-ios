# Calendario académico — límite de dominio y contrato pendiente

## Regla central

El horario semanal es una recurrencia. No crea documentos de clase para todas
las semanas del año. La app proyecta los bloques efectivos para una fecha y solo
persiste una clase o leccionario cuando existe una acción docente real.

`AcademicCalendarResolver` combina, en este orden:

1. El periodo de horario v2 publicado que contiene la fecha.
2. Excepciones de horario para todo el colegio o un `courseID`.
3. Vacaciones, feriados o suspensiones, que suprimen la recurrencia aplicable.

El horario legacy se usa únicamente cuando no existe ningún periodo v2
publicado. Si existen periodos pero la fecha queda fuera de todos ellos, el
resultado es vacío; volver al legacy en ese caso inventaría clases fuera del año
académico.

## Identidad de espacios académicos

`courseID` identifica tanto cursos oficiales como talleres. `kind` conserva la
diferencia de reglas y presentación. `aliasKeys` permite resolver nombres o
claves históricas después de renombrar un taller, sin volver a usar la etiqueta
visible como identidad principal.

## Persistencia futura

Esta pasada agrega el modelo y resolver puro, pero no inventa una colección
Firestore. Antes de implementar CRUD o importación, iOS y la plataforma local
deben acordar:

- ámbito de colegio y año académico;
- ID estable, versión y zona `America/Santiago`;
- eventos de día completo y con hora;
- curso/taller, unidad, clase y evaluación opcionales;
- política de conflictos, duplicados y edición concurrente;
- formato de importación elegido a partir de archivos reales del colegio;
- autorización, auditoría y eliminación.

PDF no debe asumirse como formato estructurado. iCalendar sería apropiado para
eventos civiles si la fuente lo ofrece; CSV o planilla requiere un mapeo explícito
de columnas. Hasta verificar esa fuente, la app no muestra un importador que
prometa guardar datos.
