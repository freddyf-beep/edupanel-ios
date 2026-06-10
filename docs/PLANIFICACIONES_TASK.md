# Tarea: Rehacer pestana Mis Planificaciones y Vista Detalle de Curso

## Objetivo
Reescribir el codigo de las vistas de Planificaciones en iOS para replicar fielmente la experiencia web de `edupanel_local`. No se trata de parchar lo actual, sino de rehacer las vistas completas siguiendo la misma estructura, logica y contenido que la web.

## Archivos web de referencia (fuente de verdad)

| Vista | Archivo web | Descripcion |
|-------|-------------|-------------|
| Hub (4 vistas) | `edupanel_local/components/edu-panel/planificaciones/planificaciones-list.tsx` | Hub principal con Timeline, Cursos, Calendario, Insights |
| Detalle curso | `edupanel_local/components/edu-panel/planificaciones/planificaciones-v2-detail.tsx` | Detalle por curso con lista de unidades inline |
| Shell router | `edupanel_local/components/edu-panel/planificaciones/planificaciones-v2-shell.tsx` | Router que decide entre lista y detalle por `?curso` |
| Tipos/datos | `edupanel_local/lib/curriculo.ts` | Modelos de datos y funciones Firestore |
| Utilidades | `edupanel_local/lib/shared.ts` | `UNIT_COLORS`, `buildUrl`, `withAsignatura`, `unidadIdFromIndex` |

## Archivos iOS a reescribir

| Archivo | Accion |
|---------|--------|
| `EduPanel/Views/Planificaciones/PlanificacionesHubView.swift` | REESCRIBIR COMPLETO |
| `EduPanel/Views/Planificaciones/PlanificacionesDetailView.swift` | REESCRIBIR COMPLETO |

## Archivos iOS que NO se tocan (ya funcionan)

| Archivo | Razon |
|---------|--------|
| `EduPanel/ViewModels/PlanificacionesViewModel.swift` | Logica de carga ya funciona |
| `EduPanel/Services/PlanificacionRepository.swift` | Capa de datos ya funciona |
| `EduPanel/Models/PlanificacionModels.swift` | Modelos ya alineados con Firestore |
| `EduPanel/Views/WebReplicaComponents.swift` | Componentes compartidos (EPWebCard, EPTheme, etc.) |
| `EduPanel/Views/AppShell.swift` | Navegacion y routing |
| `EduPanel/Views/SidebarView.swift` | Sidebar |

## Que debe tener el Hub (PlanificacionesHubView)

### Estructura general
Replicar `planificaciones-list.tsx` con estas 4 vistas en tabs:

1. **Timeline anual** - Gantt horizontal con filas por curso, barras por unidad, linea de "hoy", meses Mar-Dic
2. **Cursos** (NUEVA - no existe en iOS) - Grid de cards por curso con: avatar con iniciales, nombre, asignatura, unidades, horas, cobertura, badges en curso/proximas
3. **Calendario** - Vista mensual con hitos de inicio/fin de unidad, panel lateral de unidades activas en el mes
4. **Insights** - Sugerencias inteligentes, distribucion por tipo, cobertura por curso, proximas 30 dias, unidades sin fechas

### Hero card
- Gradiente rosa/fuchsia como la web
- Titulo: "{Asignatura} · {N} cursos"
- Subtitulo descriptivo
- Botones placeholder: Drive, IA/Asistente
- Buscador integrado

### KPIs (6 boxes)
- Total unidades (con horas totales)
- En curso
- Proximas
- Cobertura (% con fechas)
- Sin fechas
- Cursos activos

### Filtros
- Popover/boton por Curso (multi-select)
- Popover/boton por Estado: Futura, Actual, Pasada, Sin fechas
- Boton limpiar filtros
- Contador de unidades visibles

### Estados de unidad (mismos que web)
- `futura` = "Proxima" (azul)
- `actual` = "En curso" (verde)
- `pasada` = "Cerrada" (gris)
- `incompleta` = "Sin fechas" (ambar)

### Tipos de unidad (mismos que web)
- `tradicional` = "Tradicional"
- `invertida` = "Invertida"
- `proyecto` = "Proyecto"
- `unidad0` = "Unidad 0"

## Que debe tener el Detalle de Curso (PlanificacionesDetailView)

Replicar `planificaciones-v2-detail.tsx`:

### Header
- "{Asignatura} · {Curso}" en uppercase
- "Planificacion por curso"
- Contador: "{N} unidades · {horas} horas · {cobertura}% cobertura"
- Pill de estado general
- Barra de progreso de cobertura
- Botones placeholder: Drive, Exportar

### Creacion inline de unidades
- TextField para nombre
- Picker para tipo (tradicional/invertida/proyecto/unidad0)
- Boton "Agregar"
- Sin modales

### Lista de unidades (una fila por unidad)
Cada unidad muestra:
- Numero con color de fondo
- Nombre (editable con doble tap)
- Pills: tipo + estado
- Fechas o "Sin fechas" + horas
- Boton eliminar con confirmacion
- Barra de cobertura (asignados/total con %)
- 3 botones de accion: Ver, Crono, Clases (navegan a VerUnidad con initialTab)

### Sidebar derecho
- **Proximas clases**: mini lista de las proximas clases del cronograma con badge de unidad, fecha, OA
- **Resumen**: unidades, horas, con fechas, sin fechas, cobertura
- **Exportar**: placeholders para DOCX y PDF

## Reglas de implementacion

1. **Leer SOLO los archivos listados en "referencia web" y "archivos iOS a reescribir"**
2. **NO tocar** ViewModels, Services, Models, AppShell, Sidebar, WebReplicaComponents
3. Usar los componentes compartidos existentes: `EPWebCard`, `EPTheme`, `EPSectionHeader`, `EPKPIBox`, `EPStatusPill`, `EPWebTabBar`, `EPPlaceholderActionButton`, `ReplicaFlowLayout`
4. Mantener la navegacion existente via `AppRoute.coursePlanificaciones` y `AppRoute.verUnidad`
5. Los datos vienen del `PlanificacionesViewModel` y `PlanificacionRepository` existentes - no cambiar la capa de datos
6. Idioma: espanol
7. Compilar sin warnings
8. No agregar comentarios a menos que sean necesarios para claridad

## Diferencias clave iOS vs Web a considerar

| Aspecto | Web | iOS |
|---------|-----|-----|
| Layout | Grid 2 columnas (1.5fr / 1fr) | ScrollView vertical |
| Tabs | Tabs con border inferior | EPWebTabBar (capsulas) |
| Filtros | Popover de shadcn/ui | Menu o sheet nativo |
| Timeline | CSS Grid con posiciones % | ScrollView horizontal con offsets |
| Calendario | Grid 7 columnas con aspect-square | LazyVGrid |
| Navegacion | next/link con query params | NavigationLink con AppRoute |
| Drive | DriveSheet funcional | EPPlaceholderActionButton |
| IA | RecomendadorSemanticoModal | EPPlaceholderActionButton |

## Carga de datos

El ViewModel ya existe y funciona. El Hub recibe `dashboardRepository` y `planificacionRepository`.
El Detalle recibe `curso`, `asignatura`, `dashboardRepository`, `planificacionRepository`.

NO cambiar las firmas de init ni la logica de carga. Solo reescribir las Views.
