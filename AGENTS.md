# EduPanel iOS — instrucciones permanentes

Estas instrucciones se aplican a cualquier agente o conversación que trabaje en este repositorio. Antes de modificar código, leer también:

- `docs/PRODUCT_VISION.md`
- `docs/WORKING_AGREEMENT.md`

## Propósito

EduPanel debe evolucionar como una aplicación nativa de iOS para docentes. La plataforma web es una referencia funcional y de identidad, pero la aplicación móvil no debe ser una copia de sus pantallas. La navegación, jerarquía, distribución e interacción se diseñan para iPhone.

La aplicación está pensada para docentes con edades, experiencia tecnológica, capacidades y contextos de uso muy diversos. La facilidad de uso es una condición central del producto, no un detalle posterior.

## Principios de producto y diseño

- Mantener la identidad de EduPanel: propósito, personalidad, colores y tipografía. No cambiarla sin una solicitud explícita.
- Diseñar con el lenguaje actual de las aplicaciones iOS y con iOS 26 como dirección visual principal.
- Usar Liquid Glass de manera visible pero intencional, especialmente en navegación, barras, menús, controles flotantes y superficies interactivas.
- No aplicar vidrio a todo. El contenido debe conservar legibilidad, contraste y una jerarquía clara.
- Favorecer interfaces simples, familiares y rápidas de comprender. Evitar pantallas sobrecargadas, navegación profunda y opciones simultáneas innecesarias.
- Aplicar divulgación progresiva: mostrar primero lo esencial y revelar opciones avanzadas cuando la persona las necesite.
- Usar lenguaje cotidiano y docente. Evitar tecnicismos, mensajes ambiguos y acciones cuyo resultado no sea evidente.
- Reducir pasos, decisiones y escritura manual en las tareas frecuentes.
- Usar componentes y comportamientos nativos de Apple cuando resuelvan bien el problema.
- Diseñar para distintos tamaños de iPhone, orientación cuando corresponda, Dynamic Type, VoiceOver, contraste suficiente, áreas táctiles cómodas, modo claro y modo oscuro.
- Las animaciones deben explicar cambios de estado y aportar continuidad; no deben ralentizar ni distraer.
- Se pueden estudiar aplicaciones contemporáneas como referencia de comportamiento, pero EduPanel debe tener una solución propia y adecuada al trabajo docente.
- No conservar una interfaz deficiente solamente porque ya existe. Si se solicita un rediseño, proponer un sistema coherente y no limitarse a cambios cosméticos.

## Forma de trabajar

1. Entender la tarea y revisar la implementación existente antes de editar, instalar o reconstruir.
2. Conservar la lógica de negocio y los flujos que no estén dentro del alcance solicitado.
3. Para decisiones visuales importantes, revisar patrones actuales y priorizar documentación oficial de Apple. Explicar las decisiones relevantes con lenguaje claro.
4. Implementar una solución coherente con la visión del producto y con el alcance de la conversación actual.
5. Compilar y verificar los cambios antes de declararlos terminados.
6. Cuando el trabajo sea visual, probarlo en el simulador y revisar el resultado en pantalla. Usar el simulador integrado junto a Codex cuando esté disponible.
7. Informar con honestidad qué se probó, qué no se pudo probar y cualquier limitación real.

## Trabajo local y GitHub

- Trabajar localmente en este Mac por defecto.
- Se permite inspeccionar, editar, compilar y ejecutar pruebas locales necesarias para la tarea solicitada.
- No crear ramas, commits, pushes, pull requests, releases ni modificar el repositorio remoto salvo que Freddy lo pida explícitamente.
- No ejecutar GitHub Actions, generar una IPA, publicar en TestFlight ni iniciar otra forma de distribución salvo solicitud explícita.
- GitHub y la distribución son etapas opcionales de validación o entrega, normalmente al final de un trabajo; no forman parte automática de cada tarea.
- Si Freddy solicita una build con Xcode 26 en GitHub Actions, se puede preparar, subir, ejecutar y vigilar hasta obtener un resultado, siempre dentro del alcance que haya autorizado.
- Diferenciar claramente una build de simulador, una IPA sin firma, una IPA firmada y una entrega por TestFlight. Nunca afirmar que una IPA se puede instalar directamente en un iPhone sin comprobar su firma y aprovisionamiento.

## Alcance de cada conversación

- Cada conversación debe concentrarse en el tema que Freddy indique.
- Estas reglas y la visión del producto son permanentes; las decisiones puntuales de una pantalla no deben convertirse automáticamente en reglas globales.
- El código vigente es la fuente de verdad para decisiones específicas ya implementadas.
- Si una nueva solicitud contradice una decisión anterior, presentar la diferencia y seguir la instrucción más reciente de Freddy.
- No ampliar una tarea hacia otras secciones de la aplicación sin una razón técnica necesaria o autorización explícita.
