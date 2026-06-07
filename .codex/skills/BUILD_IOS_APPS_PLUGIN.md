# Que hace el plugin Build iOS Apps

El plugin Build iOS Apps es un paquete de herramientas y guias para que Codex pueda trabajar mejor en una app iOS. No es una dependencia de la app, no se instala dentro de Xcode y no cambia el codigo por si solo. Sirve para que el asistente tenga instrucciones especializadas y herramientas para leer, construir, probar, depurar y mejorar proyectos SwiftUI/iOS.

## Para que sirve en este proyecto

En esta app, el plugin ayuda principalmente a:

- revisar y editar vistas SwiftUI con mejores patrones de estructura, estado y navegacion;
- construir y ejecutar la app en el simulador de iOS;
- inspeccionar errores de compilacion, logs y comportamiento en runtime;
- revisar rendimiento de pantallas SwiftUI;
- investigar consumo de memoria, leaks o ciclos de retencion;
- crear o revisar App Intents para Shortcuts, Siri, Spotlight, widgets o controles del sistema;
- abrir el simulador en el navegador de Codex cuando haga falta verificar visualmente la app;
- aplicar patrones modernos de UI, incluyendo Liquid Glass cuando corresponda a iOS 26 o superior.

## Herramienta principal

La herramienta principal que entrega el plugin es `xcodebuildmcp`.

Con esa herramienta Codex puede, cuando este disponible:

- detectar proyectos y schemes de Xcode;
- compilar la app;
- ejecutar la app en un simulador;
- correr tests;
- lanzar la app instalada;
- capturar logs;
- inspeccionar pantallas del simulador;
- ayudar a diagnosticar fallos de build o runtime.

## Skills locales copiadas

Estas son las skills que quedaron copiadas en `.codex/skills/build-ios-apps`:

- `ios-app-intents`: guia para App Intents, entidades y shortcuts del sistema.
- `ios-debugger-agent`: flujo para compilar, ejecutar y depurar en simulador.
- `ios-ettrace-performance`: captura y analisis de rendimiento con ETTrace.
- `ios-memgraph-leaks`: investigacion de leaks y memoria.
- `ios-simulator-browser`: uso del simulador reflejado en el navegador de Codex.
- `swiftui-liquid-glass`: guia para UI Liquid Glass en iOS 26+.
- `swiftui-performance-audit`: revision de rendimiento de vistas SwiftUI.
- `swiftui-ui-patterns`: patrones de navegacion, estado, componentes y layout SwiftUI.
- `swiftui-view-refactor`: refactor de vistas SwiftUI grandes o dificiles de mantener.

## Que no hace

El plugin no reemplaza Xcode, no publica la app en App Store y no instala librerias Swift automaticamente. Tampoco garantiza que el simulador funcione si el entorno local no tiene Xcode, runtimes de iOS o permisos configurados correctamente.

## Como pedirme trabajo usando este plugin

Puedes pedirme cosas como:

- "compila la app y arregla los errores";
- "abre la app en el simulador y revisa esta pantalla";
- "refactoriza esta vista SwiftUI";
- "revisa si esta pantalla tiene problemas de rendimiento";
- "agrega App Intents para esta accion";
- "investiga por que la app crashea al iniciar";
- "verifica visualmente la UI en iPhone";
- "revisa memoria/leaks despues de navegar por la app".

Cuando el trabajo requiera simulador o build, Codex usara las herramientas del plugin. Cuando solo sea lectura o edicion de codigo, normalmente bastara con las skills y los archivos del proyecto.
