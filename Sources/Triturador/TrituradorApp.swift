import SwiftUI
import TrituradorUI

@main
struct TrituradorApp: App {
    @StateObject private var modelo = Modelo()

    var body: some Scene {
        Window("Triturador", id: "principal") {
            VistaPrincipal(modelo: modelo)
                .frame(minWidth: 720, minHeight: 580)
                // Una app soltada sobre el icono del Dock llega por aquí.
                .onOpenURL { modelo.elegir($0) }
        }
        .defaultSize(width: 800, height: 720)
        .windowStyle(.hiddenTitleBar)          // el degradado sube hasta los semáforos
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Elegir app…") { modelo.elegirConPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}
