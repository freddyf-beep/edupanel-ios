# Acuerdo de trabajo con Codex

Este documento explica cómo iniciar y conducir nuevas conversaciones sobre EduPanel sin depender del historial de un chat anterior.

## Inicio de una conversación nueva

La conversación puede comenzar con:

> Lee `AGENTS.md`, `docs/PRODUCT_VISION.md` y `docs/WORKING_AGREEMENT.md`. En esta conversación trabajaremos solamente en [tema o pantalla].

Después, indicar el resultado deseado, los problemas observados y cualquier cosa que no deba cambiar. No es necesario volver a explicar la visión completa del producto.

## Comportamiento esperado

Codex debe:

- revisar primero el código y el estado local relacionados con la tarea;
- comprobar herramientas y configuraciones existentes antes de instalar algo;
- trabajar localmente salvo instrucción contraria;
- presentar decisiones de diseño con razones comprensibles;
- implementar dentro del alcance acordado;
- compilar y probar en proporción al riesgo del cambio;
- revisar visualmente en simulador cuando se modifique interfaz o interacción;
- comunicar limitaciones o bloqueos reales sin ocultarlos;
- entregar un resumen breve de lo cambiado, las verificaciones realizadas y los archivos relevantes.

## Diseño y referencias

Cuando se solicite una propuesta o rediseño importante, Codex debe considerar la visión de EduPanel, estudiar patrones actuales cuando sea necesario y evaluar la solución desde la perspectiva de docentes con distintos niveles de experiencia tecnológica.

Las referencias externas sirven para fundamentar decisiones, no para reemplazar el criterio de producto. La solución final debe mantener la identidad de EduPanel, aprovechar las convenciones nativas de iOS y reducir complejidad.

## Simulador

Para cambios visuales, el recorrido esperado es:

1. implementar el cambio localmente;
2. compilar la aplicación;
3. abrirla en un simulador apropiado;
4. navegar hasta la pantalla modificada;
5. revisar legibilidad, jerarquía, desplazamiento, interacción y estados importantes;
6. corregir los problemas encontrados antes de entregar.

Cuando esté disponible, se debe usar la integración que permite mantener el simulador visible junto al trabajo de Codex. Una captura aislada ayuda, pero no reemplaza probar la interacción.

## GitHub y distribución

No se debe asumir que terminar una función implica publicarla.

Solo cuando Freddy lo solicite explícitamente, Codex puede realizar una o varias de estas acciones:

- crear una rama o commit;
- subir cambios a GitHub;
- abrir o actualizar un pull request;
- ejecutar y vigilar GitHub Actions;
- compilar con una versión específica de Xcode;
- generar o descargar una IPA;
- preparar firma, TestFlight u otra distribución.

La autorización debe interpretarse según la solicitud concreta. Pedir una prueba local no autoriza un push; pedir un push no autoriza una publicación en TestFlight.

## Separación de temas

Es recomendable usar conversaciones distintas para áreas grandes como navegación, dashboard, planificaciones, evaluaciones, accesibilidad, rendimiento, servidor o distribución.

Cada conversación debe mantener la visión común, pero revisar el código vigente para conocer las decisiones específicas de su área. Los documentos de tareas antiguas son antecedentes, no instrucciones permanentes, salvo que Freddy los mencione expresamente.

## Cierre de una conversación

Al finalizar, Codex debe dejar claro:

- qué resultado quedó funcionando;
- qué se cambió;
- cómo se verificó;
- qué no se verificó o qué depende de otra tarea;
- si hubo o no acciones en GitHub o distribución.

Las decisiones generales nuevas que deban aplicarse a todo el proyecto se incorporan a estos documentos únicamente cuando Freddy lo solicite o confirme.
