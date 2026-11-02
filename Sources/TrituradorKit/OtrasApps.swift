import Foundation

/// Las demás apps instaladas. Sirven para dos cosas:
///
/// 1. **No confundir restos.** Quitando «Chrome» no se puede arrastrar lo de «Chrome Canary»:
///    `com.google.Chrome.canary` empieza igual que `com.google.Chrome`, pero es de otra app.
/// 2. **Detectar lo compartido.** Dos apps del mismo fabricante pueden usar el mismo grupo de
///    datos (Word y Excel). Si se tira al quitar una, la otra pierde sus datos.
public struct OtrasApps: Sendable {
    /// Identificadores (en minúsculas) de las otras apps y de sus piezas.
    public let identificadores: Set<String>
    /// Grupo de datos (en minúsculas) → nombres de las otras apps que lo declaran.
    public let usuariosDeGrupo: [String: [String]]

    public static let ninguna = OtrasApps(identificadores: [], usuariosDeGrupo: [:])

    public init(identificadores: Set<String>, usuariosDeGrupo: [String: [String]]) {
        self.identificadores = Set(identificadores.map { $0.lowercased() })
        self.usuariosDeGrupo = Dictionary(uniqueKeysWithValues: usuariosDeGrupo.map { ($0.key.lowercased(), $0.value) })
    }

    /// Dónde se instalan las apps.
    public static func carpetasHabituales(inicio: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/Applications/Utilities"),
         URL(fileURLWithPath: "/System/Applications"),
         URL(fileURLWithPath: "/System/Applications/Utilities"),
         inicio.appendingPathComponent("Applications")]
    }

    /// `true` si `nombre` es el identificador de otra app, o empieza por él (`<id>.algo`).
    public func esDeOtra(_ nombre: String) -> Bool {
        let minusculas = nombre.lowercased()
        if identificadores.contains(minusculas) { return true }
        // Se compara contra todos los prefijos terminados en punto: `a.b.c.plist` → `a.b.c`, `a.b`, `a`.
        var partes = minusculas.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        while partes.count > 1 {
            partes.removeLast()
            if identificadores.contains(partes.joined(separator: ".")) { return true }
        }
        return false
    }

    /// Recorre las carpetas de apps (dos niveles: `/Applications/Utilidades/Foo.app` también cuenta).
    /// La app que se va a quitar y cualquier copia suya quedan fuera: no son «otras».
    public static func escanear(sin objetivo: AppObjetivo, en carpetas: [URL] = carpetasHabituales()) -> OtrasApps {
        let fm = FileManager.default
        var ids: Set<String> = []
        var grupos: [String: [String]] = [:]

        func procesar(_ app: URL) {
            if app.standardizedFileURL == objetivo.url { return }
            let propios = AppObjetivo.identificadores(de: app)
            // Otra copia de la misma app (en Descargas, por ejemplo) no es «otra app».
            if !propios.isDisjoint(with: objetivo.identificadoresPropios) { return }
            ids.formUnion(propios)
            let nombre = app.deletingPathExtension().lastPathComponent
            for grupo in AppObjetivo.leerFirma(app).grupos {
                grupos[grupo, default: []].append(nombre)
            }
        }

        for carpeta in carpetas {
            guard let hijos = try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for hijo in hijos {
                if hijo.pathExtension.lowercased() == "app" {
                    procesar(hijo)
                } else if (try? hijo.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    for nieto in (try? fm.contentsOfDirectory(at: hijo, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])) ?? []
                    where nieto.pathExtension.lowercased() == "app" {
                        procesar(nieto)
                    }
                }
            }
        }
        return OtrasApps(identificadores: ids, usuariosDeGrupo: grupos)
    }
}
