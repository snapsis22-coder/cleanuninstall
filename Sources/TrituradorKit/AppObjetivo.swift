import Foundation
import Security

/// Lectura de plists (XML o binarios) sin lanzar errores: un archivo ilegible es un `nil`.
enum Plist {
    static func leer(_ url: URL) -> [String: Any]? {
        guard let datos = try? Data(contentsOf: url),
              let objeto = try? PropertyListSerialization.propertyList(from: datos, options: [], format: nil)
        else { return nil }
        return objeto as? [String: Any]
    }
}

public enum ErrorDeApp: LocalizedError {
    case noEsApp(URL)
    case sinInfo(URL)
    case sinIdentificador(URL)

    public var errorDescription: String? {
        switch self {
        case .noEsApp(let url): "«\(url.lastPathComponent)» no es una aplicación (.app)."
        case .sinInfo(let url): "No pude leer el Info.plist de «\(url.lastPathComponent)»."
        case .sinIdentificador(let url):
            "«\(url.lastPathComponent)» no declara un identificador, así que no puedo saber qué archivos son suyos."
        }
    }
}

/// Todo lo que hay que saber de la app que se va a desinstalar: quién es (identificador, equipo
/// que la firmó), qué piezas lleva dentro y si es seguro tocarla.
///
/// **La regla de fondo:** una app de macOS es una carpeta, y su identidad es el
/// `CFBundleIdentifier` de `Contents/Info.plist`. Casi todo lo que deja atrás lleva ese texto en
/// el nombre, y por eso se busca por él y no por el nombre «bonito» de la app.
public struct AppObjetivo: Sendable {
    public let url: URL
    public let nombre: String
    public let identificador: String
    public let version: String?
    /// Nombres con los que la app puede aparecer en carpetas (sin el identificador).
    public let nombresPosibles: [String]
    /// El identificador de la app y el de cada pieza que lleva dentro (extensiones, ayudantes, XPC).
    public let identificadoresPropios: Set<String>
    /// Ayudantes privilegiados que la app instala fuera de sí misma (`SMJobBless`).
    public let ayudantesPrivilegiados: Set<String>
    /// Etiquetas de servicios que la app declara en `Contents/Library/LaunchDaemons|LaunchAgents`.
    public let etiquetasDeServicio: Set<String>
    /// `application-groups` de sus permisos: nombres de carpetas en `Group Containers`.
    public let grupos: Set<String>
    public let equipo: String?
    /// Si no es `nil`, la app no se puede triturar y éste es el motivo.
    public let motivoDeProteccion: String?

    public var estaProtegida: Bool { motivoDeProteccion != nil }
}

// MARK: - Lectura

extension AppObjetivo {

    /// Nombres de ejecutable que no dicen nada de la app (se comparten entre cientos).
    private static let ejecutablesGenericos: Set<String> = [
        "electron", "nw", "java", "python", "launcher", "main", "app", "run", "start", "node",
    ]

    public static func leer(_ url: URL, propioIdentificador: String? = Bundle.main.bundleIdentifier) throws -> AppObjetivo {
        let url = url.standardizedFileURL
        guard url.pathExtension.lowercased() == "app" else { throw ErrorDeApp.noEsApp(url) }
        guard let info = Plist.leer(url.appendingPathComponent("Contents/Info.plist")) else {
            throw ErrorDeApp.sinInfo(url)
        }
        guard let id = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty else { throw ErrorDeApp.sinIdentificador(url) }

        let archivo = url.deletingPathExtension().lastPathComponent
        let mostrado = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let corto = (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let nombre = mostrado ?? corto ?? archivo

        // Los nombres con los que puede aparecer en una carpeta, sin repetir (sin importar mayúsculas).
        var nombres: [String] = []
        func añadir(_ candidato: String?) {
            guard let candidato, candidato.count >= 3,
                  !nombres.contains(where: { $0.caseInsensitiveCompare(candidato) == .orderedSame }) else { return }
            nombres.append(candidato)
        }
        añadir(archivo)
        añadir(mostrado)
        añadir(corto)
        if let ejecutable = info["CFBundleExecutable"] as? String,
           !ejecutablesGenericos.contains(ejecutable.lowercased()) {
            añadir(ejecutable)
        }
        if let ultimo = id.split(separator: ".").last, ultimo.count >= 4 { añadir(String(ultimo)) }

        let piezas = piezasInternas(de: url)
        let firma = leerFirma(url)

        var protegida: String?
        if url.path.hasPrefix("/System/") {
            protegida = "Es parte de macOS."
        } else if id.hasPrefix("com.apple."), firmadaPorAppleComoSistema(url) {
            protegida = "Es parte de macOS."
        } else if let propio = propioIdentificador, id == propio {
            protegida = "Es el propio Triturador."
        }

        return AppObjetivo(
            url: url, nombre: nombre, identificador: id,
            version: info["CFBundleShortVersionString"] as? String,
            nombresPosibles: nombres,
            identificadoresPropios: Set([id]).union(piezas.identificadores),
            ayudantesPrivilegiados: piezas.ayudantes.union(
                (info["SMPrivilegedExecutables"] as? [String: Any]).map { Set($0.keys) } ?? []),
            etiquetasDeServicio: piezas.etiquetas,
            grupos: firma.grupos,
            equipo: firma.equipo,
            motivoDeProteccion: protegida)
    }

    // MARK: Piezas internas

    private struct Piezas {
        var identificadores: Set<String> = []
        var ayudantes: Set<String> = []
        var etiquetas: Set<String> = []
    }

    /// Busca las extensiones (`.appex`), servicios XPC, ítems de inicio y ayudantes que la app
    /// lleva dentro. **No** entra en `Frameworks`: ahí viven cosas como el actualizador Sparkle,
    /// que comparten decenas de apps y no son de ésta.
    private static func piezasInternas(de app: URL) -> Piezas {
        var piezas = Piezas()
        let contenido = app.appendingPathComponent("Contents")
        let fm = FileManager.default

        // Ayudantes de SMJobBless: ejecutables sueltos cuyo nombre es su identificador.
        if let ayudantes = try? fm.contentsOfDirectory(atPath: contenido.appendingPathComponent("Library/LaunchServices").path) {
            piezas.ayudantes.formUnion(ayudantes.filter { !$0.hasPrefix(".") })
        }
        // Servicios de SMAppService: plists con su etiqueta.
        for carpeta in ["Library/LaunchDaemons", "Library/LaunchAgents"] {
            let ruta = contenido.appendingPathComponent(carpeta)
            for archivo in (try? fm.contentsOfDirectory(at: ruta, includingPropertiesForKeys: nil)) ?? []
            where archivo.pathExtension == "plist" {
                if let etiqueta = Plist.leer(archivo)?["Label"] as? String { piezas.etiquetas.insert(etiqueta) }
            }
        }

        // Sólo se miran las carpetas donde macOS espera piezas con identidad propia. Recorrer
        // todo `Contents` sería lento (Resources y Frameworks pueden tener miles de archivos) y,
        // en Frameworks, traería cosas compartidas como el actualizador Sparkle.
        let contenedores: Set<String> = ["app", "appex", "xpc", "systemextension"]
        for carpeta in ["PlugIns", "XPCServices", "Library", "Extensions", "SystemExtensions"] {
            let raiz = contenido.appendingPathComponent(carpeta)
            guard let recorrido = fm.enumerator(at: raiz, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles]) else { continue }
            for caso in recorrido {
                guard let url = caso as? URL else { continue }
                if url.pathComponents.count - raiz.pathComponents.count > 3 {
                    recorrido.skipDescendants()
                    continue
                }
                guard contenedores.contains(url.pathExtension.lowercased()),
                      let info = Plist.leer(url.appendingPathComponent("Contents/Info.plist")),
                      let id = info["CFBundleIdentifier"] as? String, !id.isEmpty else { continue }
                piezas.identificadores.insert(id)
                recorrido.skipDescendants()      // lo que haya dentro de la pieza ya es de la pieza
            }
        }
        return piezas
    }

    /// El identificador de una app y el de cada pieza que lleva dentro.
    static func identificadores(de app: URL) -> Set<String> {
        guard let id = Plist.leer(app.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String,
              !id.isEmpty else { return [] }
        return Set([id]).union(piezasInternas(de: app).identificadores)
    }

    // MARK: Firma

    struct Firma {
        var equipo: String?
        var grupos: Set<String> = []
    }

    /// El equipo que firmó la app y los grupos de datos que declara. Para apps de otros se usa
    /// igual, así se sabe qué grupos comparte cada una.
    static func leerFirma(_ url: URL) -> Firma {
        var codigo: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &codigo) == errSecSuccess, let codigo else {
            return Firma()
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(codigo, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let datos = info as? [String: Any] else { return Firma() }
        let derechos = datos[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return Firma(equipo: datos[kSecCodeInfoTeamIdentifier as String] as? String,
                     grupos: Set(derechos?["com.apple.security.application-groups"] as? [String] ?? []))
    }

    /// `anchor apple` es el requisito que cumple el software firmado por Apple mismo (Safari,
    /// Mail…). Las apps de Apple que se bajan de la App Store (Pages, Keynote…) NO lo cumplen,
    /// y ésas sí se pueden desinstalar.
    private static func firmadaPorAppleComoSistema(_ url: URL) -> Bool {
        var codigo: SecStaticCode?
        var requisito: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &codigo) == errSecSuccess, let codigo,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &requisito) == errSecSuccess,
              let requisito else { return false }
        return SecStaticCodeCheckValidity(codigo, SecCSFlags(rawValue: kSecCSBasicValidateOnly), requisito) == errSecSuccess
    }
}
