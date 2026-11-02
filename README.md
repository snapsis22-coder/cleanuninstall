# Triturador

Desinstalador para macOS. Arrastras una app y busca lo que deja escondido (preferencias, cachés,
servicios en segundo plano, ayudantes con permisos, recibos de instalación) para mandarlo a la
Papelera. Nada se borra de verdad.

- **Se busca por identificador**, no por nombre: `com.fabricante.App`, sus piezas internas, los
  grupos de datos que declara y lo que ejecutan sus demonios.
- **Lo ajeno no se toca**: otras apps instaladas (Chrome vs Chrome Canary), `com.apple.*`, carpetas
  compartidas con otras apps. Sólo se marca de entrada lo seguro.
- **Apaga el servicio antes de tirar su `.plist`** (`launchctl bootout`).
- Una sola contraseña de administrador para lo que está en `/Library`.

## Compilar

    ./build_app.sh                 # compila, firma e instala en /Applications
    swift run trituradortests      # pruebas (contra un sistema de mentira)
    .build/debug/trituradortests --buscar /Applications/Algo.app   # qué encontraría (sólo lee)
    swift run trituradorshot <carpeta>                             # retratos de la interfaz
