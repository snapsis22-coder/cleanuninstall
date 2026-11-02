import AppKit
import SwiftUI
import TrituradorUI

/// Renderiza la interfaz a PNG sin abrir ventana, para poder revisarla sin depender del permiso
/// de grabación de pantalla del sistema.
///
///     swift run trituradorshot <carpeta-de-salida>
///
/// ⚠ Sólo sirve para vistas de SwiftUI puro. `ScrollView`, `List` y `Form` están hechas sobre
/// AppKit y ImageRenderer no las sabe pintar fuera de pantalla: por eso las pantallas se
/// retratan con `sinScroll`. Los iconos de las apps (NSImage) sí salen.

@MainActor
func retratar<V: View>(_ vista: V, _ nombre: String, en carpeta: URL,
                       ancho: CGFloat = 800, alto: CGFloat = 720, oscuro: Bool = false) {
    NSApp.appearance = NSAppearance(named: oscuro ? .darkAqua : .aqua)
    let renderizador = ImageRenderer(content:
        vista.frame(width: ancho, height: alto)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, oscuro ? .dark : .light)
    )
    renderizador.scale = 2
    guard let imagen = renderizador.nsImage,
          let tiff = imagen.tiffRepresentation,
          let mapa = NSBitmapImageRep(data: tiff),
          let png = mapa.representation(using: .png, properties: [:]) else {
        print("  ✗ no se pudo renderizar \(nombre)")
        return
    }
    let destino = carpeta.appendingPathComponent("\(nombre).png")
    try? png.write(to: destino)
    print("  ✓ \(destino.path)")
}

guard let salida = CommandLine.arguments.dropFirst().first.map({ URL(fileURLWithPath: $0) }) else {
    print("uso: trituradorshot <carpeta-de-salida>")
    exit(1)
}
try? FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    retratar(Retratos.inicio(), "1-inicio", en: salida)
    retratar(Retratos.inicio(), "1b-inicio-alto", en: salida, alto: 1380)
    retratar(Retratos.resultados(), "4b-resultados-bajo", en: salida, alto: 720)
    retratar(Retratos.inicio(soltando: true), "2-inicio-soltando", en: salida)
    retratar(Retratos.inicio(sinAcceso: true, aviso: "«Notas» no se puede triturar. Es parte de macOS."), "3-inicio-avisos", en: salida)
    retratar(Retratos.resultados(), "4-resultados", en: salida, alto: 1380)
    retratar(Retratos.resultados(abierta: true, sinAcceso: true), "5-resultados-avisos", en: salida, alto: 1460)
    retratar(Retratos.triturando(), "6-triturando", en: salida)
    retratar(Retratos.listo(), "7-listo", en: salida)
    retratar(Retratos.listo(conFallos: true), "8-listo-con-fallos", en: salida)
    retratar(Retratos.dibujo(), "9-dibujo", en: salida, ancho: 840, alto: 220)
    retratar(Retratos.inicio(), "10-inicio-oscuro", en: salida, oscuro: true)
    retratar(Retratos.resultados(), "11-resultados-oscuro", en: salida, alto: 1380, oscuro: true)
}
