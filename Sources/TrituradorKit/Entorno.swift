import Foundation

/// Dónde está «el disco»: la carpeta del usuario y la raíz del sistema. En la app son las de
/// verdad; en las pruebas son carpetas temporales con un sistema de mentira, para poder probar
/// la búsqueda sin tocar nada real.
public struct Entorno: Sendable {
    public let inicio: URL
    public let raiz: URL
    public let uid: UInt32
    public let gid: UInt32
    /// `/private/var/folders/…/C` y `/T`: cachés y temporales por usuario. Vacío en pruebas.
    public let carpetasTemporales: [URL]

    public init(inicio: URL, raiz: URL, uid: UInt32 = getuid(), gid: UInt32 = getgid(),
                carpetasTemporales: [URL] = []) {
        self.inicio = inicio.standardizedFileURL
        self.raiz = raiz.standardizedFileURL
        self.uid = uid
        self.gid = gid
        self.carpetasTemporales = carpetasTemporales
    }

    public static var real: Entorno {
        Entorno(inicio: FileManager.default.homeDirectoryForCurrentUser,
                raiz: URL(fileURLWithPath: "/"),
                carpetasTemporales: [_CS_DARWIN_USER_CACHE_DIR, _CS_DARWIN_USER_TEMP_DIR].compactMap(rutaDeConfstr))
    }

    var bibliotecaDelUsuario: URL { inicio.appendingPathComponent("Library") }
    var bibliotecaDelSistema: URL { raiz.appendingPathComponent("Library") }
    var recibos: URL { raiz.appendingPathComponent("private/var/db/receipts") }

    /// La Papelera del usuario.
    var papelera: URL { inicio.appendingPathComponent(".Trash") }

    private static func rutaDeConfstr(_ nombre: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(nombre, &buffer, buffer.count) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }
}

// MARK: - Catálogo

/// Una carpeta donde las apps dejan cosas, y cómo se mira dentro de ella.
struct Ubicacion {
    enum Ambito { case usuario, sistema }

    enum Modo {
        /// Cada hijo se clasifica por su nombre de archivo.
        case archivos
        /// Igual, y además se mira dentro de la carpeta del fabricante (`Google/Chrome`).
        case anidable
        /// `Group Containers`: carpetas que las apps comparten con sus hermanas.
        case grupos
        /// Complementos: si el nombre no dice nada, se lee el `Info.plist` de dentro.
        case complementos
        /// `LaunchAgents` / `LaunchDaemons`: se leen los `.plist` y se mira qué ejecutan.
        case servicios(ServicioLaunchd.Dominio)
        /// `PrivilegedHelperTools`: ayudantes que la app instaló con permisos de administrador.
        case ayudantes
        /// Informes de fallo, que se llaman `Nombre_fecha_equipo.ips`.
        case informes
    }

    let ambito: Ambito
    /// Ruta relativa a la carpeta `Library` del ámbito (o a la raíz si `desdeRaiz`).
    let ruta: String
    let categoria: Categoria
    let tipo: String
    let modo: Modo
    var desdeRaiz = false

    func carpeta(en entorno: Entorno) -> URL {
        if desdeRaiz { return entorno.raiz.appendingPathComponent(ruta) }
        let base = ambito == .usuario ? entorno.bibliotecaDelUsuario : entorno.bibliotecaDelSistema
        return base.appendingPathComponent(ruta)
    }

    /// Todas las carpetas donde se busca. **Lo que no esté aquí nunca se toca**: `Guardia` lo
    /// comprueba antes de mover cualquier cosa.
    static func catalogo(en entorno: Entorno) -> [(ubicacion: Ubicacion, carpeta: URL)] {
        var lista: [Ubicacion] = [
            // — Del usuario (~/Library) —
            .init(ambito: .usuario, ruta: "Application Support", categoria: .datos, tipo: "Datos", modo: .anidable),
            .init(ambito: .usuario, ruta: "Containers", categoria: .datos, tipo: "Contenedor", modo: .archivos),
            .init(ambito: .usuario, ruta: "Group Containers", categoria: .datos, tipo: "Datos compartidos", modo: .grupos),
            .init(ambito: .usuario, ruta: "Preferences", categoria: .datos, tipo: "Preferencias", modo: .archivos),
            .init(ambito: .usuario, ruta: "Preferences/ByHost", categoria: .datos, tipo: "Preferencias", modo: .archivos),
            .init(ambito: .usuario, ruta: "Saved Application State", categoria: .datos, tipo: "Estado guardado", modo: .archivos),
            .init(ambito: .usuario, ruta: "Application Scripts", categoria: .datos, tipo: "Scripts", modo: .archivos),
            .init(ambito: .usuario, ruta: "Caches", categoria: .cache, tipo: "Caché", modo: .anidable),
            .init(ambito: .usuario, ruta: "HTTPStorages", categoria: .cache, tipo: "Datos de red", modo: .archivos),
            .init(ambito: .usuario, ruta: "WebKit", categoria: .cache, tipo: "Datos web", modo: .archivos),
            .init(ambito: .usuario, ruta: "Cookies", categoria: .cache, tipo: "Cookies", modo: .archivos),
            .init(ambito: .usuario, ruta: "Logs", categoria: .cache, tipo: "Registros", modo: .anidable),
            .init(ambito: .usuario, ruta: "Logs/DiagnosticReports", categoria: .cache, tipo: "Informe de fallo", modo: .informes),
            .init(ambito: .usuario, ruta: "LaunchAgents", categoria: .servicios, tipo: "Agente", modo: .servicios(.usuario)),

            // — Del sistema (/Library) —
            .init(ambito: .sistema, ruta: "Application Support", categoria: .datos, tipo: "Datos", modo: .anidable),
            .init(ambito: .sistema, ruta: "Preferences", categoria: .datos, tipo: "Preferencias", modo: .archivos),
            .init(ambito: .sistema, ruta: "Caches", categoria: .cache, tipo: "Caché", modo: .anidable),
            .init(ambito: .sistema, ruta: "Logs", categoria: .cache, tipo: "Registros", modo: .anidable),
            .init(ambito: .sistema, ruta: "Logs/DiagnosticReports", categoria: .cache, tipo: "Informe de fallo", modo: .informes),
            // Los agentes de /Library/LaunchAgents corren en la sesión del usuario, no como root.
            .init(ambito: .sistema, ruta: "LaunchAgents", categoria: .servicios, tipo: "Agente", modo: .servicios(.usuario)),
            .init(ambito: .sistema, ruta: "LaunchDaemons", categoria: .servicios, tipo: "Demonio", modo: .servicios(.sistema)),
            .init(ambito: .sistema, ruta: "PrivilegedHelperTools", categoria: .servicios, tipo: "Ayudante privilegiado", modo: .ayudantes),

            // — Recibos de instalación —
            .init(ambito: .sistema, ruta: "private/var/db/receipts", categoria: .recibos, tipo: "Recibo", modo: .archivos, desdeRaiz: true),
        ]

        // Complementos: viven en las dos bibliotecas con el mismo nombre de carpeta.
        let complementos: [(String, String)] = [
            ("Internet Plug-Ins", "Complemento de navegador"), ("PreferencePanes", "Panel de Ajustes"),
            ("QuickLook", "Vista rápida"), ("Spotlight", "Importador de Spotlight"),
            ("Audio/Plug-Ins/Components", "Complemento de audio"), ("Audio/Plug-Ins/VST", "Complemento de audio"),
            ("Audio/Plug-Ins/VST3", "Complemento de audio"), ("Audio/Plug-Ins/HAL", "Controlador de audio"),
            ("Audio/MIDI Drivers", "Controlador MIDI"), ("Input Methods", "Método de entrada"),
            ("Screen Savers", "Salvapantallas"), ("ColorPickers", "Selector de color"),
        ]
        for ambito in [Ambito.usuario, .sistema] {
            for (ruta, tipo) in complementos {
                lista.append(.init(ambito: ambito, ruta: ruta, categoria: .complementos, tipo: tipo, modo: .complementos))
            }
        }
        lista.append(.init(ambito: .sistema, ruta: "Extensions", categoria: .complementos, tipo: "Extensión del kernel", modo: .complementos))
        lista.append(.init(ambito: .usuario, ruta: "Services", categoria: .complementos, tipo: "Servicio del menú", modo: .complementos))

        var resultado = lista.map { ($0, $0.carpeta(en: entorno)) }
        // Cachés y temporales por usuario (`/private/var/folders/…`): sólo cuentan los hijos
        // llamados como la app.
        for carpeta in entorno.carpetasTemporales {
            resultado.append((.init(ambito: .usuario, ruta: carpeta.path, categoria: .cache, tipo: "Temporales", modo: .archivos), carpeta))
        }
        return resultado
    }
}
