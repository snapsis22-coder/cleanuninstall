import SwiftUI
import TrituradorUI

@main
struct TrituradorApp: App {
    @StateObject private var modelo = Modelo()

    init() { Actualizaciones.compartido.arrancar() }

    var body: some Scene {
        Window("Triturador", id: "principal") {
            VistaPrincipal(modelo: modelo)
                .frame(minWidth: 720, minHeight: 580)
                // Una app soltada sobre el icono del Dock llega por aquí.
                .onOpenURL { modelo.elegir($0) }
                .onAppear {
                    // Triturando no se cierra la app a medias.
                    Actualizaciones.compartido.ocupada = { [modelo] in
                        if case .triturando = modelo.fase { return true } else { return false }
                    }
                }
        }
        .defaultSize(width: 800, height: 720)
        .windowStyle(.hiddenTitleBar)          // el degradado sube hasta los semáforos
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Elegir app…") { modelo.elegirConPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) { ComandosDeActualizacion() }
        }
    }
}
