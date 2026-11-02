import AppKit
import SwiftUI
import TrituradorKit
import UniformTypeIdentifiers

/// Qué se marca en la lista. `personalizada` es lo que queda cuando el usuario marca a mano.
enum ModoDeSeleccion: Hashable {
    case seguros, probables, todo, personalizada
}

/// Todo lo que la ventana necesita saber. La lógica de verdad vive en `TrituradorKit`; esto sólo
/// la conduce y se la presenta a SwiftUI.
@MainActor
public final class Modelo: ObservableObject {

    public enum Fase {
        case vacio
        case analizando(nombre: String)
        case resultados(Resultado)
        case triturando
        case listo(Informe, AppObjetivo)
    }

    @Published public private(set) var fase: Fase = .vacio
    @Published var seleccion: Set<URL> = []
    /// Un mensaje para la pantalla de inicio («eso no es una app»).
    @Published var aviso: String?
    @Published private(set) var accesoTotal = Permisos.accesoTotalAlDisco()

    public init() {}

    /// Para los retratos: arranca ya en una pantalla concreta.
    init(fase: Fase, seleccion: Set<URL> = [], aviso: String? = nil, accesoTotal: Bool = true) {
        self.fase = fase
        self.seleccion = seleccion
        self.aviso = aviso
        self.accesoTotal = accesoTotal
    }

    // MARK: Elegir una app

    /// Recibe lo que el usuario soltó o eligió. Sólo se admite una app a la vez.
    func recibir(_ proveedores: [NSItemProvider]) {
        guard let proveedor = proveedores.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return }
        proveedor.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { dato, _ in
            guard let datos = dato as? Data, let url = URL(dataRepresentation: datos, relativeTo: nil) else { return }
            Task { @MainActor in self.elegir(url) }
        }
    }

    public func elegir(_ url: URL) {
        switch fase {
        case .vacio: break
        default: return          // ya hay una app en curso: primero se termina o se cancela
        }
        let app: AppObjetivo
        do { app = try AppObjetivo.leer(url) } catch {
            aviso = error.localizedDescription
            return
        }
        if let motivo = app.motivoDeProteccion {
            aviso = "«\(app.nombre)» no se puede triturar. \(motivo)"
            return
        }
        aviso = nil
        accesoTotal = Permisos.accesoTotalAlDisco()
        fase = .analizando(nombre: app.nombre)
        Task {
            let resultado = await Buscador().buscar(app)
            seleccion = Set(resultado.elementos.filter(\.marcadoDeEntrada).map(\.url))
            fase = .resultados(resultado)
        }
    }

    public func elegirConPanel() {
        let panel = NSOpenPanel()
        panel.title = "Elige la app que quieres quitar"
        panel.prompt = "Elegir"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { elegir(url) }
    }

    /// Vuelve a la pantalla de inicio.
    func reiniciar() {
        seleccion = []
        aviso = nil
        accesoTotal = Permisos.accesoTotalAlDisco()
        fase = .vacio
    }

    func actualizarPermisos() { accesoTotal = Permisos.accesoTotalAlDisco() }

    // MARK: Selección

    var resultado: Resultado? {
        if case .resultados(let r) = fase { return r }
        return nil
    }

    var seleccionados: [Elemento] { resultado?.elementos.filter { seleccion.contains($0.url) } ?? [] }
    var bytesSeleccionados: Int64 { seleccionados.reduce(0) { $0 + $1.tamaño } }

    func alternar(_ elemento: Elemento) {
        if seleccion.contains(elemento.url) { seleccion.remove(elemento.url) } else { seleccion.insert(elemento.url) }
    }

    /// Marca o desmarca todo un grupo.
    func alternar(grupo elementos: [Elemento]) {
        let todosMarcados = elementos.allSatisfy { seleccion.contains($0.url) }
        for e in elementos { if todosMarcados { seleccion.remove(e.url) } else { seleccion.insert(e.url) } }
    }

    private func conjunto(_ modo: ModoDeSeleccion) -> Set<URL> {
        guard let elementos = resultado?.elementos else { return [] }
        switch modo {
        case .seguros: return Set(elementos.filter { $0.confianza == .exacta }.map(\.url))
        case .probables: return Set(elementos.filter { $0.confianza != .dudosa }.map(\.url))
        case .todo: return Set(elementos.map(\.url))
        case .personalizada: return seleccion
        }
    }

    /// El modo se deduce de lo que está marcado: si coincide con uno, ese; si no, «personalizada».
    var modo: ModoDeSeleccion {
        get {
            for candidato in [ModoDeSeleccion.seguros, .probables, .todo] where conjunto(candidato) == seleccion { return candidato }
            return .personalizada
        }
        set { if newValue != .personalizada { seleccion = conjunto(newValue) } }
    }

    // MARK: Triturar

    func triturar() async {
        guard let resultado, !seleccionados.isEmpty else { return }
        let elegidos = seleccionados
        guard confirmar(resultado, elegidos) else { return }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: resultado.app.identificador).isEmpty {
            fase = .triturando
            guard await CerrarApp.cerrar(resultado.app) else {
                fase = .resultados(resultado)
                alerta("«\(resultado.app.nombre)» no se cerró",
                       "Ciérrala tú (⌘Q) y vuelve a pulsar «Triturar». Si tiene un documento sin guardar, es ella quien lo pregunta.")
                return
            }
        }
        fase = .triturando
        let informe = await Papelera().triturar(elegidos, de: resultado.app, conAdmin: true)
        fase = .listo(informe, resultado.app)
    }

    /// Reintenta con permisos de administrador lo que falló por falta de ellos.
    func reintentarConAdmin() async {
        guard case .listo(let previo, let app) = fase else { return }
        let pendientes = previo.fallos.filter(\.necesitaAdmin)
        guard !pendientes.isEmpty else { return }
        fase = .triturando
        let nuevo = await Papelera().triturar(pendientes.map(\.elemento), de: app, conAdmin: true, todoComoAdmin: true)
        fase = .listo(Informe(enviados: previo.enviados + nuevo.enviados,
                              fallos: previo.fallos.filter { !$0.necesitaAdmin } + nuevo.fallos,
                              serviciosApagados: previo.serviciosApagados + nuevo.serviciosApagados), app)
    }

    // MARK: Diálogos

    /// Antes de mover nada se dice exactamente qué va a pasar, sobre todo lo que pide contraseña.
    private func confirmar(_ resultado: Resultado, _ elegidos: [Elemento]) -> Bool {
        let admin = elegidos.filter(\.requiereAdmin).count
        let servicios = elegidos.filter { $0.servicio != nil }.count
        var lineas = ["Se mandarán a la Papelera (\(Formato.bytes(elegidos.reduce(0) { $0 + $1.tamaño }))). "
                      + "Podrás recuperarlos de ahí hasta que la vacíes."]
        if servicios > 0 { lineas.append("Antes se apagarán \(servicios) servicio\(servicios == 1 ? "" : "s") en segundo plano.") }
        if admin > 0 {
            lineas.append("\(admin) elemento\(admin == 1 ? " está" : "s están") en carpetas del sistema: macOS te pedirá tu contraseña una vez.")
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: resultado.app.identificador).isEmpty == false {
            lineas.append("«\(resultado.app.nombre)» está abierta: se cerrará primero.")
        }
        let alerta = NSAlert()
        alerta.messageText = "¿Triturar \(elegidos.count) elemento\(elegidos.count == 1 ? "" : "s") de «\(resultado.app.nombre)»?"
        alerta.informativeText = lineas.joined(separator: "\n\n")
        alerta.addButton(withTitle: "Triturar")
        alerta.addButton(withTitle: "Cancelar")
        alerta.alertStyle = .warning
        return alerta.runModal() == .alertFirstButtonReturn
    }

    private func alerta(_ titulo: String, _ texto: String) {
        let a = NSAlert()
        a.messageText = titulo
        a.informativeText = texto
        a.runModal()
    }
}

// MARK: - Formato

enum Formato {
    private static let formateador: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func bytes(_ n: Int64) -> String {
        n < 1000 ? "0 KB" : formateador.string(fromByteCount: n)
    }

    /// `/Users/yo/Library/Caches/x` → `~/Library/Caches/x`
    static func ruta(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
