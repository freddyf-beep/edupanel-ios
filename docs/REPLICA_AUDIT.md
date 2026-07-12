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
| Mi Perfil - Mis Cursos | `perfil-shell.tsx` `CursosView` | Replica visual/lectura en avance | Falta edicion completa de curso/estudiantes/color como web | Probar curso con asignaturas, bloques, estudiantes y PIE |
| Mi Perfil - Asignaturas | `perfil-shell.tsx` `AsignaturasView` | Parcial | Faltan textos de ayuda y mapeo compacto igual a web | Probar cursos oficiales/taller/libre |
| Mi Perfil - Identidad | `perfil-shell.tsx` `IdentidadView` | Parcial | Falta subida/cambio real de logos en la misma pantalla | Probar guardar perfil, colegio y encabezado |
| Mi Perfil - Conexiones | `perfil-shell.tsx` `ConexionesViewV2` | Placeholder | No lee estado real Calendar/Drive | Probar cuenta conectada/desconectada |
| Planificaciones - Hub | `planificaciones-list.tsx` | En correccion de datos | Ahora debe leer todas las asignaturas guardadas, no solo la primera preferencia | Probar mismos cursos/asignaturas que web |
| Planificaciones - Detalle curso | `planificaciones-v2-detail.tsx` | En correccion de datos | La ruta debe conservar asignatura para IDs, cobertura, acciones y sidebar | Probar Ver/Crono/Clases sin cargar defaults falsos |
| Actividades de clase | `/actividades`, `ver-unidad-v3-clases.tsx` | Hub nativo v1 | Falta vista transversal de progreso por actividad, IA e importaciones de la web | Entrar desde Inicio/menú, filtrar asignatura/curso y abrir una unidad directamente en Clases |
| Evaluaciones - Pruebas | `evaluaciones/pruebas/*`, `lib/pruebas.ts` | Hub + detalle + editor nativo v1 | Faltan importación Word, IA/PIE, aplicación/corrección, banco, historial y exportación | Crear/editar los 7 tipos, probar conflictos web/iOS, colegio principal/secundario y contenido desconocido |
| Evaluaciones - Guías | `evaluaciones/guias/*`, `lib/guias.ts`, `document-download.tsx` | Hub + detalle + editor + PDF nativo/formato institucional v1 | Falta IA, DOCX/Word, impresión explícita y limpieza de medios huérfanos | Probar CRUD, currículo, PhotosPicker/Storage, 13 tipos, plantillas y PDF alumno/pauta en dispositivo real |
| Ver Unidad - Unidad | `ver-unidad-v3-dashboard.tsx` | Parcial | Falta paridad visual de header, estado, recursos, estrategias | Probar unidad con HTML, archivos y actividades |
| Ver Unidad - Cronograma | `ver-unidad-v3-cronograma.tsx` | Parcial | Matriz OA x clases y alertas deben mostrar toda cobertura | Probar asignacion OA y persistencia |
| Ver Unidad - Clases | `ver-unidad-v3-clases.tsx` | Edición nativa v1 | Falta IA, importación Word/Notebook, Drive y autosave de la web | Editar objetivo, momentos, indicadores y recursos; guardar, reabrir y lanzar Clase en vivo |

## Fallas confirmadas

- `Mi Perfil` sigue implementado dentro de `PlaceholderModuleView.swift`; debe salir a modulo propio cuando se cierre la replica.
- `Mi Semana` no replicaba la grilla visual de calendario de la web.
- El flujo de Ver Unidad necesitaba resolver mejor IDs `1`, `unidad_1` y `unidadCurricularId` para no cargar datos por defecto.
- `Clases` podia fallar por render HTML complejo; el render seguro ya evita importar HTML con `NSAttributedString`.
- La app perdia la `asignatura` al navegar a Planificaciones/Ver Unidad. La web construye IDs con asignatura + curso + unidad; si iOS usa la primera asignatura del perfil, busca documentos distintos y muestra defaults o datos incompletos.
- `PlanificacionesHubView` cargaba una sola asignatura desde preferencias. Para replica web debe leer los planes guardados en `planificaciones_curso` y agrupar cronogramas por asignatura/curso/unidad.
- `AppShell` solo resolvia `Ver Unidad` dentro del stack de Planificaciones. Las mismas rutas desde otras pestanas caian en placeholder, rompiendo continuidad.
- `Actividades de clase` apuntaba por error a `Cronograma`. Ahora tiene un hub propio por asignatura, curso y unidad que reutiliza el mismo editor de Clases y abre la ruta con `initialTab: "clases"`.
- `Ver Unidad > Clases` tenia seleccion de clase debil: si la actividad no existia en memoria, los editores trabajaban sobre un fallback no persistido. La seleccion ahora normaliza/crea la actividad antes de renderizar.
- `Ver Unidad > Clases` ya permite editar y guardar desde iOS el objetivo, inicio, desarrollo, cierre, contexto, adecuacion, indicadores, habilidades, actitudes, materiales, TIC y estado de cada clase. Guarda parches por campo, preserva datos avanzados/adjuntos y conserva un borrador local hasta confirmar la sincronizacion.
- La carga de Unidad, Cronograma y Clases distingue documento inexistente de error de red o formato invalido. Ante un fallo, iOS bloquea la edicion y ofrece reintento para no sembrar una plantilla vacia sobre datos web existentes.
- `Evaluaciones` ya replica las cuatro pestañas web. `Pruebas` lee el colegio activo, conserva el payload Firestore raw, acepta aliases de los siete tipos, muestra estímulos/recursos y carga la aplicación solo dentro del detalle.
- `Pruebas` ya permite crear, editar, duplicar y eliminar dentro del usuario/colegio activo. El editor cubre configuración, currículo/OA, instrucciones, secciones, estímulos, recursos y selección múltiple, verdadero/falso, pareados, ordenar, completar, respuesta corta y desarrollo.
- El guardado de Pruebas relee dentro de una transacción Firestore, rechaza una edición conocida concurrente y fusiona por `sourceId` o índice+huella. Conserva campos futuros, aliases, miembros no interpretados y borrados explícitos; una prueba `aplicada` queda de solo lectura.
- Las imágenes de bloques de Pruebas usan `PhotosPicker`, compresión bajo 8 MB y la ruta propia `users/{uid}/evaluaciones/pruebas/{pruebaId}/...`; una prueba nueva debe guardarse antes de subir medios.
- `Guías` ya lee el mismo documento Firestore y ámbito de colegio que la web, sin exigir `createdAt`. El decoder conserva el payload raw, renderiza texto/imagen/tabla/separador, las 13 actividades declaradas, cierre y metadatos curriculares; los tipos futuros quedan señalados sin perderse.
- `Guías` permite crear, editar cabecera/instrucciones, duplicar entre cursos y eliminar. Los guardados existentes verifican que el documento siga presente y usan parches top-level; la duplicación conserva el payload completo y regenera IDs internos conocidos.
- El editor de `Guías` ya agrega/reordena secciones y edita texto, imagen por URL, tabla, separador y cierre. El guardado vuelve a leer el raw actual, fusiona campos conocidos por ID o posición heredada y recarga el documento canónico; actividades y bloques desconocidos quedan protegidos.
- Las 13 actividades declaradas por `lib/guias.ts` ya tienen edición nativa: alternativas/VF, completar, respuesta corta, ordenar, pareados, encerrar, marcar, colorear, dibujar, investigar, sopa de letras y abierta. Opciones, recursos, puntaje y OA también se fusionan de forma lossless; huellas de contenido evitan normalizar elementos no tocados.
- Las imágenes de bloques, opciones y colorear ya se seleccionan con `PhotosPicker`, se validan, redimensionan/comprimen bajo 8 MB y suben a `users/{uid}/evaluaciones/guias/{guiaId}/...` mediante Firebase Storage con progreso. Una guía nueva debe guardarse antes; no se borra el medio anterior hasta tener una estrategia post-guardado para evitar referencias rotas al descartar.
- `Guías` reutiliza el selector curricular nativo de Rúbricas/Listas: resuelve nivel, unidades y OA reales, mezcla la selección guardada y persiste `oas` junto con `metadatosCurriculares` derivados. Si un documento heredado no tiene `oas`, su metadata raw se conserva salvo que el selector resuelva explícitamente la unidad.
- `Guías` exporta PDF A4 multipágina para alumno y pauta desde el detalle o el editor, incluso con cambios aún no guardados. Renderiza los cuatro bloques y las 13 actividades, incrusta imágenes HTTPS o `data:image` validadas en orden determinista, avisa los recursos omitidos y ofrece vista previa PDFKit más compartir/guardar. La pauta marca alternativas y respuestas sin alterar el documento Firestore.
- La exportación carga identidad y `formatos_export` desde el mismo scope principal/colegio de la guía, con fallback legado solo cuando no existe ningún colegio moderno. Replica la prioridad `guia`/`todos`, permite elegir plantilla y aplica fuente, tamaño, color, margen, alineación, modo de encabezado, logos, visibilidad de OA/instrucciones, sombreado/bordes, firmas, pie y numeración. El membrete y pie configurado se repiten por página como adaptación nativa de `UIPrintPageRenderer`.
- Al guardar una guía se recalcula `puntajeMaximo` desde las actividades vigentes. Al quitar cualquiera de los logos del colegio, el perfil ahora envía `FieldValue.delete()` para que el guardado con merge no restaure el logo anterior.
- La carga de Listas, Rúbricas, Pruebas y Guías ahora usa estados de error independientes y un token de generación: un fallo o una respuesta tardía de otro curso no vacía ni reemplaza instrumentos válidos.

## Regla de cierre por pantalla

Una pantalla solo se considera lista cuando:

- Compila en GitHub Actions.
- El IPA contiene `Payload/EduPanel.app/EduPanel`.
- Se instala y se abre en el iPhone.
- Muestra los mismos cursos/asignaturas/unidades/datos que la web.
- Las acciones visibles no rompen navegacion.
- Los textos con HTML se leen formateados o al menos limpios.
