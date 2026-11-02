import AppKit
import Foundation

/// Los permisos de privacidad que le hacen falta a Triturador para ver (y mover) los datos de
/// otras apps.
public enum Permisos {

    /// «Acceso total al disco». La prueba es abrir la base de datos de permisos del sistema, que
    /// macOS sólo deja leer a quien lo tiene.
    public static func accesoTotalAlDisco() -> Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    public static func abrirAjustesDeAccesoTotal() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
