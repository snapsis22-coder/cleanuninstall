import AppKit

/// Hasta la 1.1.0 la app se llamaba Triturador. El actualizador de esa versión instala la
/// nueva encima de /Applications/Triturador.app (el DMG lleva una copia oculta con ese
/// nombre). Al abrirse ahí, la app se cambia sola el nombre a CleanUninstall.app y se
/// vuelve a abrir desde la ruta nueva. El identificador no cambia, así que los permisos
/// (Acceso total al disco) siguen valiendo.
enum CambioDeNombre {
    static let viejo = "Triturador.app"
    static let nuevo = "CleanUninstall.app"

    /// Devuelve true si se está renombrando (y la app va a cerrarse para reabrirse).
    static func siHaceFalta() -> Bool {
        let actual = Bundle.main.bundleURL
        guard actual.lastPathComponent == viejo else { return false }
        // La copia del DMG viene marcada como oculta (para que no se vea junto a la
        // visible); en Aplicaciones tiene que verse, se renombre o no.
        var valores = URLResourceValues()
        valores.isHidden = false
        var visible = actual
        try? visible.setResourceValues(valores)

        let destino = actual.deletingLastPathComponent().appendingPathComponent(nuevo)
        let gestor = FileManager.default
        // Si ya hay un CleanUninstall al lado (instalado a mano), no se toca nada
        guard !gestor.fileExists(atPath: destino.path) else { return false }
        do { try gestor.moveItem(at: actual, to: destino) } catch { return false }

        let configuracion = NSWorkspace.OpenConfiguration()
        configuracion.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destino, configuration: configuracion) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
