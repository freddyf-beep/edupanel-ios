# Sesión de pulido UI — cambios aplicados

> Fecha: 20 y 21 de julio de 2026
> Agente: pulido de detalles (división: Codex hace trabajo pesado, este agente hace detalles)

---

## Resumen

| # | Cambio | Archivo(s) | Estado |
|---|--------|-----------|--------|
| 1 | Limpiar "Hazlo rápido" (quitar Calificar + Actividades) | `DashboardView.swift` | ✅ |
| 2 | Botón ocultar/mostrar Tab Bar acoplado al borde derecho | `AppShell.swift` | ✅ |
| 3 | Toggle claro/oscuro oculto en el ícono del saludo (🌙) | `DashboardView.swift` | ✅ |
| 4 | Menú lateral rediseñado estilo Twitter/X | `SidebarView.swift`, `SidebarContainer.swift` | ✅ |
| 5 | Perfil: Banner compacto + Barra unificada de KPIs + Limpieza | `ProfileView.swift`, `ProfileSummaryTab.swift` | ✅ |
| 6 | Mi Semana: Reordenación (1→3→4→2) + Calendario Móvil sin scroll horizontal | `ProfileWeekTab.swift` | ✅ |
| 7 | Mi Semana: Rediseño "Lista detallada" estilo iOS 26 Inset Grouped | `ProfileWeekTab.swift` | ✅ |
| 8 | Mi Semana: Exportación de horario a PDF (Vertical / Horizontal) | `ScheduleExportView.swift`, `ProfileWeekTab.swift`, `ProfileView.swift` | ✅ |
| 9 | Cronograma: Limpieza de KPIs/Filtros + Rediseño Móvil de Semana y Lista | `CronogramaView.swift`, `CronogramaSemanaView.swift`, `CronogramaListaView.swift` | ✅ |
| 10 | Herramienta de Dictado por Voz (Prototipo nativo iOS) | `DictadoService.swift`, `DictadoModalView.swift`, `Info.plist`, `DashboardView.swift` | ✅ |

---

## 1. "Hazlo rápido" limpiado

**Archivo:** `EduPanel/Views/DashboardView.swift`

Se eliminaron las quick actions **Calificar** y **Actividades** del carrusel horizontal "Hazlo rápido". Quedan solo:

- **Planificar** → abre Planificaciones
- **Mi Perfil** → abre Perfil

---

## 2. Botón ocultar/mostrar Tab Bar

**Archivo:** `EduPanel/Views/AppShell.swift`

Se agregó un botón circular pequeño (chevron ˇ / ^) acoplado al borde derecho de la `FloatingTabBar`, mitad dentro y mitad fuera de la cápsula, como una manija integrada.

---

## 3. Toggle claro/oscuro oculto en la luna 🌙

**Archivo:** `EduPanel/Views/DashboardView.swift`

El ícono del saludo es un botón oculto que alterna entre modo claro y oscuro manteniendo su aspecto visual.

---

## 4. Menú lateral rediseñado estilo Twitter/X

**Archivos:** `EduPanel/Views/SidebarView.swift`, `EduPanel/Views/SidebarContainer.swift`

Header plano alineado a la izquierda (Avatar, Nombre, Email, Stats), filas de navegación sin chips, secciones expandibles ("Mis cursos", "Configuración y soporte"), footer con toggle de apariencia y scrim interactivo que sigue el gesto de arrastre.

---

## 5. Perfil: Banner compacto + Barra unificada de KPIs + Limpieza

**Archivos:** `EduPanel/Views/Profile/ProfileView.swift`, `EduPanel/Views/Profile/Tabs/ProfileSummaryTab.swift`

### Qué se hizo
- **Banner compacto**: Reducción de la altura del degradado superior a 1/3 de su tamaño original (`132pt` → `44pt` en modo normal; `88pt` → `30pt` en modo simple). El botón de la paleta se redujo a `28x28`.
- **Barra unificada de KPIs**: Reemplazo de la cuadrícula `LazyVGrid` de 6 tarjetas por una barra horizontal unificada compacta de 3 indicadores clave (**Cursos**, **Horas Clase**, **Alumnos**), separados por `Divider`s.
- **Limpieza de resumen**: Eliminación de las secciones "Tu progreso" y "Atajos rápidos" en `ProfileSummaryTab.swift`.

---

## 6. Mi Semana: Reordenación y Calendario Móvil

**Archivo:** `EduPanel/Views/Profile/Tabs/ProfileWeekTab.swift`

### Qué se hizo
- **Reordenación de secciones**: La pestaña se reorganizó en la secuencia **1 → 3 → 4 → 2** (Constructor de horario → Vista calendario → Lista detallada → Bloques no lectivos).
- **Calendario Semanal para iPhone**: Refactorización de `ProfileWeekCalendar` eliminando la tabla horizontal de 5 columnas (port de la web) que forzaba scroll lateral. Ahora cuenta con un **Selector de Día Superior (LUN a VIE)** con puntos indicadores de actividad, y despliega el día seleccionado en una **línea de tiempo vertical de ancho completo (`maxWidth: .infinity`)**.
- **Estabilidad de compilación Swift**: Sub-expresiones de la vista aisladas en propiedades computadas (`daySelector`, `hourColumn`, `dayColumn`) y rangos numéricos envueltos en `Array(...)` para prevenir errores de chequeo de tipos en Swift.

---

## 7. Mi Semana: Lista detallada estilo iOS 26 Inset Grouped

**Archivo:** `EduPanel/Views/Profile/Tabs/ProfileWeekTab.swift`

### Qué se hizo
- **Contenedor agrupado**: Los bloques de cada día se agrupan en una única tarjeta redondeada gris (`Color(.tertiarySystemGroupedBackground)`) con `Divider`s finos con sangría de `28pt`.
- **Fila ultra compacta (`ProfileScheduleRow`)**: Reemplazo del bloque de hora gigante por una cápsula vertical de color (`4x26pt`), rango de tiempo alineado, título de clase y pastilla de asignatura. Reducción de altura por fila a casi el 50%.
- **Menú contextual de 3 puntos**: Reemplazo de los botones circulares visibles de lápiz y basura por un único botón `Menu` con el ícono `ellipsis`, que despliega las opciones nativas de **Editar bloque** y **Eliminar**.

---

## 8. Exportación de Horario a PDF (Vertical y Horizontal)

**Archivos:** `EduPanel/Views/Profile/Views/ScheduleExportView.swift` (nuevo), `EduPanel/Views/Profile/Tabs/ProfileWeekTab.swift`, `EduPanel/Views/Profile/ProfileView.swift`, `EduPanel.xcodeproj/project.pbxproj`

### Qué se hizo
- **Exportador vectorial de PDF**: Creado `ScheduleExporter` usando `ImageRenderer` (iOS 16+) y `CGContext` para renderizar el horario a un documento PDF vectorial de alta calidad en tamaño carta.
- **Menú de Orientación**: El botón "Exportar horario" ahora es un `Menu` que permite al docente elegir entre:
  - 📄 **Vertical (Carta)**: Format portrait (8.5" × 11"), con cálculo dinámico de altura de fila (`rowHeight`) para garantizar que quepa en una sola hoja.
  - 📃 **Horizontal (Apaisado)**: Format landscape (11" × 8.5"), ideal para ver columnas de día más anchas.
- **Grilla y Encabezados Nítidos**: Incluye nombre del docente, logo de EduPanel, marcas de tiempo de media hora (`:30`), líneas divisorias cada 30 minutos, colores sólidos y pie de página con fecha de generación.
- **Share Sheet Nativo**: Presentación con `UIActivityViewController` para imprimir, guardar en Archivos o enviar por AirDrop/correo, además de guardar una copia directa en el Escritorio.

---

## 9. Cronograma: Limpieza y Rediseño Móvil

**Archivos:** `EduPanel/Views/Cronograma/CronogramaView.swift`, `EduPanel/Views/Cronograma/CronogramaSemanaView.swift`, `EduPanel/Views/Cronograma/CronogramaListaView.swift`

### Qué se hizo
- **Limpieza de pantalla**: Eliminación de la grilla de KPIs (`kpiGrid`) y el panel de Filtros (`filtrosSection`) de `CronogramaView.swift`, despejando el espacio superior de la pantalla.
- **Vista "Semana" Móvil (`CronogramaSemanaView`)**: Se reemplazó el scroll horizontal de 5 columnas por un **Selector de Día Superior (LUN a VIE)** con números de fecha. Al tocar un día, sus actividades y bloques de clase se muestran a **ancho completo** (`maxWidth: .infinity`) en tarjetas grandes y legibles.
- **Vista "Lista" Móvil (`CronogramaListaView`)**: Actividades agrupadas por semana en tarjetas estilo iOS 26 Inset Grouped con divisores internos y botón contextual de tres puntos (`ellipsis`) para editar o eliminar.

---

## 10. Herramienta de Dictado por Voz (Prototipo nativo iOS) ✨ NUEVO

**Archivos:** `EduPanel/Services/DictadoService.swift` (nuevo), `EduPanel/Views/DictadoModalView.swift` (nuevo), `EduPanel/Resources/Info.plist`, `EduPanel/Views/DashboardView.swift`

### Qué se hizo
- **Servicio de Voz Nativo (`DictadoService.swift`)**: Implementado motor de reconocimiento de voz de Apple (`SFSpeechRecognizer` con localización `es-CL`) y motor de audio `AVAudioEngine` que transcribe voz a texto palabra por palabra en tiempo real. Incluye cálculo de nivel RMS para alimentar la animación de audio.
- **Permisos de Sistema**: Agregadas las claves `NSSpeechRecognitionUsageDescription` y `NSMicrophoneUsageDescription` en `Info.plist`.
- **Modal de Dictado (`DictadoModalView.swift`)**:
  - Diseño estilo **Liquid Glass / iOS 26**.
  - Cuadro de texto interactivo que muestra la transcripción en vivo.
  - Animación de **ondas de voz (waveform)** reactiva a la voz del docente.
  - Botón de micrófono circular con halo animado de pulsación.
  - Acciones rápidas para **Copiar texto** al portapapeles con feedback háptico y **Limpiar**.
- **Acceso Rápido en Inicio**: Integrado botón **"Dictado voz"** (`mic.fill`) en la sección *"Hazlo rápido"* de `DashboardView.swift` que despliega el modal.

---

## Notas técnicas generales

- **Tipografía:** System Fonts nativas en todas las vistas (`.system(size:weight:)`)
- **Colores:** Uso consistente de `EPTheme` y colores de sistema (`Color(.secondarySystemGroupedBackground)`, `Color(.tertiarySystemGroupedBackground)`)
- **Animaciones:** Transiciones fluidas con `EPTheme.spring`
- **Verificación:** Compilación limpia (`** BUILD SUCCEEDED **`) y ejecución verificada en simulador de iPhone.
