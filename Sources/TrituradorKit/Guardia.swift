import Foundation

/// Tamaño de archivos y carpetas en disco.
enum Tamaño {
    /// Lo que ocupa de verdad (bloques asignados), que es lo que Finder llama «tamaño en disco».
    /// No sigue enlaces simbólicos: cuenta el enlace, no lo que apunta.
    static func de(_ url: URL) -> Int64 {
        let claves: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let valores = try? url.resourceValues(forKeys: claves) else { return 0 }
        guard valores.isDirectory == true, valores.isSymbolicLink != true else {
            return Int64(valores.totalFileAllocatedSize ?? 0)
        }
        guard let recorrido = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(claves), options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for caso in recorrido {
            guard let hijo = caso as? URL, let v = try? hijo.resourceValues(forKeys: claves),
                  v.isDirectory != true || v.isSymbolicLink == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// El último control antes de mover algo. Aunque el buscador se equivoque, aquí se frena lo que
/// no debería tocarse jamás.
public enum Guardia {

    /// `nil` si se puede mover; si no, el motivo en cristiano.
    ///
    /// Se puede mover sólo lo que está **estrictamente dentro** de una carpeta del catálogo, o la
    /// propia app. Nunca una carpeta del catálogo entera (`~/Library/Caches`), nunca nada de
    /// macOS y nunca lo de Apple si la app que se quita no es de Apple.
    public static func rechazo(_ elemento: Elemento, app: AppObjetivo, entorno: Entorno) -> String? {
        if let motivo = app.motivoDeProteccion { return motivo }

        let ruta = elemento.url.standardizedFileURL.path
        if ruta.contains("/../") || ruta.hasSuffix("/..") { return "Ruta sospechosa." }

        // Con un sistema de mentira (pruebas) las rutas cuelgan de otra raíz: se miran sin ella.
        let relativa: String = {
            let base = entorno.raiz.path
            return base != "/" && ruta.hasPrefix(base + "/") ? String(ruta.dropFirst(base.count)) : ruta
        }()
        let protegidas = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc"]
        if protegidas.contains(where: { relativa == $0 || relativa.hasPrefix($0 + "/") }) {
            return "Está en una zona protegida de macOS."
        }

        if ruta == app.url.path {
            return elemento.categoria == .aplicacion ? nil : "Ruta inesperada."
        }

        let nombre = elemento.url.lastPathComponent.lowercased()
        if nombre.hasPrefix("com.apple."), !app.identificador.lowercased().hasPrefix("com.apple.") {
            return "Es de Apple, no de esta app."
        }

        let dentroDeCatalogo = Ubicacion.catalogo(en: entorno).contains { _, carpeta in
            let base = carpeta.standardizedFileURL.path
            return ruta.hasPrefix(base + "/") && ruta != base
        }
        return dentroDeCatalogo ? nil : "No está en ninguna de las carpetas donde CleanUninstall busca."
    }
}
