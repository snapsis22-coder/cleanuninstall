import Foundation

/// En qué grupo se muestra cada resto. El orden de los casos es el orden de la lista.
public enum Categoria: Int, CaseIterable, Comparable, Sendable {
    case aplicacion
    case servicios
    case datos
    case cache
    case complementos
    case recibos

    public var titulo: String {
        switch self {
        case .aplicacion: "Aplicación"
        case .servicios: "Servicios en segundo plano"
        case .datos: "Datos y ajustes"
        case .cache: "Cachés y registros"
        case .complementos: "Complementos y extensiones"
        case .recibos: "Recibos de instalación"
        }
    }

    public var icono: String {
        switch self {
        case .aplicacion: "app.fill"
        case .servicios: "gearshape.2.fill"
        case .datos: "folder.fill"
        case .cache: "internaldrive.fill"
        case .complementos: "puzzlepiece.extension.fill"
        case .recibos: "doc.text.fill"
        }
    }

    public static func < (a: Categoria, b: Categoria) -> Bool { a.rawValue < b.rawValue }
}

/// Qué tan seguros estamos de que un archivo es de la app. De ello depende si
/// aparece marcado de entrada.
public enum Confianza: Int, Comparable, Sendable {
    /// Lleva el identificador de la app, o ejecuta algo que está dentro de ella.
    case exacta
    /// Sólo coincide el nombre. Puede ser de otra cosa que se llame igual.
    case porNombre
    /// Empieza como la app pero no es ella, o la comparte con otra app instalada.
    case dudosa

    public var etiqueta: String {
        switch self {
        case .exacta: "Segura"
        case .porNombre: "Por nombre"
        case .dudosa: "Dudosa"
        }
    }

    public static func < (a: Confianza, b: Confianza) -> Bool { a.rawValue < b.rawValue }
}

/// Un servicio de launchd (agente o demonio) que hay que apagar antes de tirar su `.plist`.
/// Si se manda a la Papelera el archivo con el servicio vivo, éste sigue corriendo hasta
/// que se reinicie el Mac.
public struct ServicioLaunchd: Hashable, Sendable {
    public enum Dominio: Hashable, Sendable {
        /// LaunchAgents: viven en la sesión del usuario (`gui/<uid>`).
        case usuario
        /// LaunchDaemons: viven en el sistema y apagarlos exige administrador.
        case sistema
    }

    public let etiqueta: String
    public let dominio: Dominio

    public init(etiqueta: String, dominio: Dominio) {
        self.etiqueta = etiqueta
        self.dominio = dominio
    }
}

/// Un archivo o carpeta que se puede mandar a la Papelera.
public struct Elemento: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let categoria: Categoria
    /// Qué es, en una o dos palabras: «Preferencias», «Demonio», «Caché»…
    public let tipo: String
    public let confianza: Confianza
    /// Por qué lo encontramos, para que quien mira pueda juzgarlo.
    public let motivo: String
    /// `true` si el usuario no puede moverlo solo (está en `/Library`, es de root…).
    public let requiereAdmin: Bool
    public var tamaño: Int64
    public let servicio: ServicioLaunchd?
    /// Una advertencia extra: «También la usa Excel».
    public let nota: String?

    public init(url: URL, categoria: Categoria, tipo: String, confianza: Confianza, motivo: String,
                requiereAdmin: Bool, tamaño: Int64 = 0, servicio: ServicioLaunchd? = nil, nota: String? = nil) {
        self.url = url
        self.categoria = categoria
        self.tipo = tipo
        self.confianza = confianza
        self.motivo = motivo
        self.requiereAdmin = requiereAdmin
        self.tamaño = tamaño
        self.servicio = servicio
        self.nota = nota
    }

    /// Marcado de entrada sólo lo que es seguro. Lo demás lo decide quien mira.
    public var marcadoDeEntrada: Bool { confianza == .exacta }

    public var nombre: String { url.lastPathComponent }
}

/// Lo que devuelve una búsqueda.
public struct Resultado: Sendable {
    public let app: AppObjetivo
    public let elementos: [Elemento]
    /// Carpetas que no se pudieron leer (casi siempre por falta de «Acceso total al disco»).
    public let carpetasSinAcceso: [URL]
    /// La app está abierta ahora mismo.
    public let estaAbierta: Bool

    public init(app: AppObjetivo, elementos: [Elemento], carpetasSinAcceso: [URL] = [], estaAbierta: Bool = false) {
        self.app = app
        self.elementos = elementos
        self.carpetasSinAcceso = carpetasSinAcceso
        self.estaAbierta = estaAbierta
    }

    public var tamañoTotal: Int64 { elementos.reduce(0) { $0 + $1.tamaño } }
}

/// Lo que pasó al triturar.
public struct Informe: Sendable {
    public struct Fallo: Sendable {
        public let elemento: Elemento
        public let motivo: String
        /// Falló por permisos: tiene sentido reintentarlo como administrador.
        public let necesitaAdmin: Bool

        public init(elemento: Elemento, motivo: String, necesitaAdmin: Bool) {
            self.elemento = elemento
            self.motivo = motivo
            self.necesitaAdmin = necesitaAdmin
        }
    }

    public let enviados: [Elemento]
    public let fallos: [Fallo]
    /// Servicios que se apagaron antes de tirar su archivo.
    public let serviciosApagados: [String]

    public init(enviados: [Elemento], fallos: [Fallo], serviciosApagados: [String]) {
        self.enviados = enviados
        self.fallos = fallos
        self.serviciosApagados = serviciosApagados
    }

    public var bytesLiberados: Int64 { enviados.reduce(0) { $0 + $1.tamaño } }
}
