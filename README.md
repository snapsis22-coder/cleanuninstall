# CleanUninstall

*(Antes se llamaba Triturador.)*

Desinstalador para macOS. Arrastras una app y busca lo que deja escondido (preferencias, cachés,
servicios en segundo plano, ayudantes con permisos, recibos de instalación) para mandarlo a la
Papelera. Nada se borra de verdad.

- **Se busca por identificador**, no por nombre: `com.fabricante.App`, sus piezas internas, los
  grupos de datos que declara y lo que ejecutan sus demonios.
- **Lo ajeno no se toca**: otras apps instaladas (Chrome vs Chrome Canary), `com.apple.*`, carpetas
  compartidas con otras apps. Sólo se marca de entrada lo seguro.
- **Apaga el servicio antes de tirar su `.plist`** (`launchctl bootout`).
- Una sola contraseña de administrador para lo que está en `/Library`.

## Instalar

Descarga el `.dmg` de [Releases](../../releases), ábrelo y arrastra la app a Applications. La primera vez: Ajustes del Sistema › Privacidad y Seguridad › *Abrir de todos modos*. Para que encuentre todo, dale *Acceso total al disco*.

Las versiones siguientes se instalan desde la propia app: al abrir (como mucho una vez al día) o desde el menú **CleanUninstall › Buscar actualizaciones…**, avisa si hay una nueva en Releases y la instala solo si pulsas **Actualizar**. Con **CleanUninstall › Actualizar automáticamente** (viene apagado) la baja sola, la instala al cerrar la app y avisa al abrirla. Antes comprueba que el DMG coincida con el hash que publica GitHub y que la app esté firmada con el mismo certificado; la versión vieja va a la Papelera. Como la descarga no pasa por el navegador, macOS no vuelve a pedir *Abrir de todos modos*.

## Compilar

    ./build_app.sh                 # compila, firma e instala en /Applications
    swift run trituradortests      # pruebas (contra un sistema de mentira)
    ./build_dmg.sh                 # DMG con fondo y LÉEME
    ./publicar.sh 1.2.0 "notas"    # pruebas, DMG, etiqueta y Release
    .build/debug/trituradortests --buscar /Applications/Algo.app   # qué encontraría (sólo lee)
    swift run trituradorshot <carpeta>                             # retratos de la interfaz
