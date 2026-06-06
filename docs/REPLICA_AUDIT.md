# EduPanel iOS - Auditoria de replica web

Este documento deja una estructura fija para revisar la app nativa contra la web antes de dar por terminada una pantalla.

## Criterio de replica

- La fuente de verdad visual y funcional es la web existente.
- SwiftUI debe implementar vistas nativas, sin WebView.
- No basta con una version parecida: cada pantalla debe conservar secciones, jerarquia, acciones visibles, datos y estados.
- Si una accion web aun no existe en iOS, debe quedar visible con placeholder nativo claro.
- Los datos deben venir de los mismos documentos Firestore/API que usa la web.

## Pantallas objetivo

| Pantalla iOS | Fuente web | Estado actual | Riesgo principal | Siguiente evidencia requerida |
| --- | --- | --- | --- | --- |
| Mi Perfil - Resumen | `perfil-shell.tsx` `ResumenView` | Parcial | Layout movil no replica columnas y atajos web completos | Captura iOS comparada con web usando mismos datos |
| Mi Perfil - Mi Semana | `perfil-shell.tsx` `SemanaView` | En correccion | Antes era lista simple, no grilla calendario | IPA mostrando cabecera, grupos no lectivos, calendario y lista |
| Mi Perfil - Mis Cursos | `perfil-shell.tsx` `CursosView` | Parcial | Falta edicion completa de curso/estudiantes/color como web | Probar curso con estudiantes y PIE |
| Mi Perfil - Asignaturas | `perfil-shell.tsx` `AsignaturasView` | Parcial | Faltan textos de ayuda y mapeo compacto igual a web | Probar cursos oficiales/taller/libre |
| Mi Perfil - Identidad | `perfil-shell.tsx` `IdentidadView` | Parcial | Falta subida/cambio real de logos en la misma pantalla | Probar guardar perfil, colegio y encabezado |
| Mi Perfil - Conexiones | `perfil-shell.tsx` `ConexionesViewV2` | Placeholder | No lee estado real Calendar/Drive | Probar cuenta conectada/desconectada |
| Planificaciones - Hub | `planificaciones-list.tsx` | Parcial avanzado | Debe mantener timeline/cursos/calendario/insights y todos los datos | Probar mismos cursos/asignaturas que web |
| Planificaciones - Detalle curso | `planificaciones-v2-detail.tsx` | Parcial avanzado | IDs de unidad, cobertura, acciones y sidebar deben coincidir | Probar Ver/Crono/Clases sin cargar defaults falsos |
| Ver Unidad - Unidad | `ver-unidad-v3-dashboard.tsx` | Parcial | Falta paridad visual de header, estado, recursos, estrategias | Probar unidad con HTML, archivos y actividades |
| Ver Unidad - Cronograma | `ver-unidad-v3-cronograma.tsx` | Parcial | Matriz OA x clases y alertas deben mostrar toda cobertura | Probar asignacion OA y persistencia |
| Ver Unidad - Clases | `ver-unidad-v3-clases.tsx` | En correccion | Crash anterior y campos IA/HTML incompletos | Entrar a Clases, cambiar clase, guardar y reabrir |

## Fallas confirmadas

- `Mi Perfil` sigue implementado dentro de `PlaceholderModuleView.swift`; debe salir a modulo propio cuando se cierre la replica.
- `Mi Semana` no replicaba la grilla visual de calendario de la web.
- El flujo de Ver Unidad necesitaba resolver mejor IDs `1`, `unidad_1` y `unidadCurricularId` para no cargar datos por defecto.
- `Clases` podia fallar por render HTML complejo; el render seguro ya evita importar HTML con `NSAttributedString`.

## Regla de cierre por pantalla

Una pantalla solo se considera lista cuando:

- Compila en GitHub Actions.
- El IPA contiene `Payload/EduPanel.app/EduPanel`.
- Se instala y se abre en el iPhone.
- Muestra los mismos cursos/asignaturas/unidades/datos que la web.
- Las acciones visibles no rompen navegacion.
- Los textos con HTML se leen formateados o al menos limpios.
