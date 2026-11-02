import Foundation

/// Decide si un nombre de archivo es de la app y con qué seguridad.
///
/// Es la parte que más importa del programa: un error aquí es llevarse archivos de otra app.
/// Por eso se razona en tres pasos, de más a menos seguro, y **cualquier duda baja la
/// confianza** en vez de subirla.
///
///  1. **Identificador propio.** `com.fabricante.App`, o `com.fabricante.App.plist` y los demás
///     sufijos que macOS añade. Es lo único que se marca de entrada.
///  2. **Lo ajeno se descarta.** Si empieza por el identificador de *otra* app instalada, o por
///     `com.apple.`, no se toca.
///  3. **Nombre.** Se llama igual que la app. Puede ser de otra cosa: queda sin marcar.
struct Clasificador {
    struct Veredicto: Equatable {
        let confianza: Confianza
        let motivo: String
    }

    let app: AppObjetivo
    let otras: OtrasApps

    /// Identificadores propios en minúsculas, de más largo a más corto: `com.a.b.widget` tiene
    /// que probarse antes que `com.a.b`, o el sufijo se interpretaría mal.
    private let propios: [String]
    private let nombres: [String]

    init(app: AppObjetivo, otras: OtrasApps) {
        self.app = app
        self.otras = otras
        self.propios = app.identificadoresPropios.map { $0.lowercased() }.sorted { $0.count > $1.count }
        self.nombres = app.nombresPosibles.map { $0.lowercased() }.filter { !Self.demasiadoComunes.contains($0) }
    }

    /// Lo que macOS añade detrás de un identificador para fabricar nombres de archivo.
    static let sufijosConocidos: Set<String> = [
        "plist", "savedstate", "binarycookies", "plist.lockfile", "lockfile",
        "lssharedfilelist.plist", "lssharedfilelist.plist.lockfile", "sfl", "sfl2", "sfl3",
        "shipit", "log", "ips", "crash", "diag", "bom",
    ]

    /// Nombres tan genéricos que coincidir con ellos no prueba nada.
    static let demasiadoComunes: Set<String> = [
        "application", "library", "cache", "caches", "data", "logs", "log", "preferences", "support",
        "shared", "helper", "updater", "scripts", "default", "common", "temp", "tmp", "resources",
        "plugins", "plug-ins", "installer", "services", "launcher", "update", "agent", "daemon",
    ]

    /// Extensiones que no cuentan al comparar nombres: `Foo.vst3` y `Foo.plist` son «Foo».
    private static let extensionesQueNoCuentan: Set<String> = [
        "plist", "log", "savedstate", "app", "vst", "vst3", "component", "qlgenerator", "prefpane",
        "plugin", "bundle", "saver", "kext", "service", "mdimporter", "colorpicker", "ips",
    ]

    func clasificar(_ nombreDeArchivo: String) -> Veredicto? {
        let n = nombreDeArchivo.lowercased()

        // 1. Identificador propio.
        for id in propios {
            if n == id { return Veredicto(confianza: .exacta, motivo: "Mismo identificador que la app") }
            guard n.hasPrefix(id + ".") else { continue }
            let resto = String(n.dropFirst(id.count + 1))
            if Self.esSufijoConocido(resto) {
                return Veredicto(confianza: .exacta, motivo: "Lleva el identificador de la app")
            }
            // Empieza como la app pero lo que sigue no es un sufijo conocido: puede ser de otra
            // app del mismo fabricante (Chrome y Chrome Canary) o de una pieza nuestra.
            if otras.esDeOtra(n) { return nil }
            return Veredicto(confianza: .dudosa, motivo: "Empieza por el identificador de la app, pero no es idéntico")
        }

        // 2. Lo ajeno no se toca.
        if n.hasPrefix("com.apple.") { return nil }
        if otras.esDeOtra(n) { return nil }

        // 3. Por nombre.
        let base = Self.sinExtensionIgnorable(n)
        if nombres.contains(base) {
            return Veredicto(confianza: .porNombre, motivo: "Se llama igual que la app")
        }
        return nil
    }

    /// Informes de fallo: `Nombre_2026-11-02-103000_equipo.ips`.
    func clasificarInforme(_ nombreDeArchivo: String) -> Veredicto? {
        let n = nombreDeArchivo.lowercased()
        let extensiones: Set<String> = ["ips", "crash", "diag", "spin", "hang"]
        guard extensiones.contains((n as NSString).pathExtension) else { return nil }
        for nombre in nombres where n.hasPrefix(nombre + "_") {
            return Veredicto(confianza: .porNombre, motivo: "Informe de un fallo de la app")
        }
        return nil
    }

    /// El nombre de la carpeta del fabricante que sale en los ids (`com.google.Chrome` → `google`).
    var fabricante: String? {
        let partes = app.identificador.lowercased().split(separator: ".").map(String.init)
        guard partes.count >= 3 else { return nil }
        let candidato = partes[1]
        let noValen: Set<String> = ["github", "gitlab", "sourceforge", "apple", "app", "mac", "macos"]
        return candidato.count >= 3 && !noValen.contains(candidato) ? candidato : nil
    }

    /// ¿Esta carpeta es del fabricante de la app? `Google` para `com.google.Chrome`, pero también
    /// `Logitech.localized` para `com.logi.optionsplus`: basta con que una empiece por la otra.
    func esCarpetaDelFabricante(_ nombre: String) -> Bool {
        guard let fabricante else { return false }
        let n = nombre.lowercased()
        return n.count >= 3 && (n.hasPrefix(fabricante) || fabricante.hasPrefix(n))
    }

    // MARK: Piezas

    static func esSufijoConocido(_ resto: String) -> Bool {
        if sufijosConocidos.contains(resto) { return true }
        // Preferencias «ByHost»: `com.foo.App.<UUID del Mac>.plist`.
        return resto.range(of: #"^[0-9a-f-]{8,}\.plist$"#, options: .regularExpression) != nil
    }

    static func sinExtensionIgnorable(_ nombre: String) -> String {
        let extensionDelNombre = (nombre as NSString).pathExtension
        guard extensionesQueNoCuentan.contains(extensionDelNombre) else { return nombre }
        return (nombre as NSString).deletingPathExtension
    }
}
