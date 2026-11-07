import AppKit
import Foundation

/// Manda a la Papelera lo que el usuario eligió. **Nunca borra:** todo se puede sacar de la
/// Papelera hasta que el usuario la vacíe.
///
/// Orden de trabajo, pensado para que un fallo a medias deje todo recuperable:
///  1. Se pasa cada elemento por `Guardia`.
///  2. Se **apagan** los servicios de launchd. Si se tira el `.plist` con el servicio vivo, éste
///     sigue corriendo hasta el próximo reinicio.
///  3. Se mueven los restos y, **al final**, la propia app: si algo falla antes, la app sigue
///     ahí y se puede volver a buscar.
public struct Papelera: Sendable {
    public typealias Mover = @Sendable (URL) throws -> Void
    public typealias Ejecutor = @Sendable (_ programa: String, _ argumentos: [String]) -> (estado: Int32, salida: String)

    let entorno: Entorno
    let mover: Mover
    let ejecutar: Ejecutor

    /// `mover` y `ejecutar` se pueden cambiar para las pruebas.
    public init(entorno: Entorno = .real,
                mover: @escaping Mover = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                ejecutar: @escaping Ejecutor = Papelera.ejecutarDeVerdad) {
        self.entorno = entorno
        self.mover = mover
        self.ejecutar = ejecutar
    }

    /// - Parameters:
    ///   - conAdmin: si es `true` se piden permisos de administrador (una sola vez) para lo que
    ///     está en `/Library` y similares. Si es `false`, eso queda como fallo reintentable.
    ///   - todoComoAdmin: manda también lo «normal» por la vía de administrador. Es para
    ///     reintentar lo que falló por permisos aun estando en la carpeta del usuario.
    public func triturar(_ elementos: [Elemento], de app: AppObjetivo, conAdmin: Bool,
                         todoComoAdmin: Bool = false) async -> Informe {
        var enviados: [Elemento] = []
        var fallos: [Informe.Fallo] = []
        var apagados: [String] = []

        // 1. Guardia.
        var aceptados: [Elemento] = []
        for elemento in elementos {
            if let motivo = Guardia.rechazo(elemento, app: app, entorno: entorno) {
                fallos.append(.init(elemento: elemento, motivo: motivo, necesitaAdmin: false))
            } else {
                aceptados.append(elemento)
            }
        }

        // 2. Apagar los servicios del usuario (no piden contraseña).
        for elemento in aceptados {
            guard let servicio = elemento.servicio, servicio.dominio == .usuario else { continue }
            let resultado = ejecutar("/bin/launchctl", ["bootout", "gui/\(entorno.uid)/\(servicio.etiqueta)"])
            if resultado.estado == 0 { apagados.append(servicio.etiqueta) }   // distinto de 0: no estaba cargado
        }

        // 3a. Lo que el usuario puede mover solo. La app, la última.
        let delUsuario = aceptados.filter { !todoComoAdmin && !$0.requiereAdmin }
            .sorted { ($0.categoria == .aplicacion ? 1 : 0) < ($1.categoria == .aplicacion ? 1 : 0) }
        let delSistema = aceptados.filter { todoComoAdmin || $0.requiereAdmin }

        for elemento in delUsuario {
            if !existe(elemento.url) { continue }       // ya no estaba (la app y su carpeta, por ejemplo)
            do {
                try mover(elemento.url)
                enviados.append(elemento)
            } catch {
                fallos.append(.init(elemento: elemento, motivo: Self.explicar(error),
                                    necesitaAdmin: Self.esDePermisos(error)))
            }
        }

        // 3b. Lo que necesita administrador, en un solo bloque.
        if !delSistema.isEmpty {
            if conAdmin {
                let r = await comoAdministrador(delSistema)
                enviados += r.enviados
                fallos += r.fallos
                apagados += r.apagados
            } else {
                for elemento in delSistema {
                    fallos.append(.init(elemento: elemento, motivo: "Necesita permiso de administrador.",
                                        necesitaAdmin: true))
                }
            }
        }
        return Informe(enviados: enviados, fallos: fallos, serviciosApagados: apagados)
    }

    private func existe(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // MARK: Administrador

    private struct ResultadoAdmin {
        var enviados: [Elemento] = []
        var fallos: [Informe.Fallo] = []
        var apagados: [String] = []
    }

    private func comoAdministrador(_ elementos: [Elemento]) async -> ResultadoAdmin {
        let guion = Self.guionDeAdministrador(elementos, papelera: entorno.papelera, uid: entorno.uid, gid: entorno.gid)
        let aviso = "CleanUninstall necesita permiso para mover a la Papelera archivos del sistema que dejó la app."
        let resultado = ejecutar("/usr/bin/osascript", ["-e", Self.appleScript(guion, aviso: aviso)])

        var salida = ResultadoAdmin()
        // El usuario canceló la contraseña, o falló antes de empezar.
        if resultado.estado != 0 {
            let cancelado = resultado.salida.contains("-128") || resultado.salida.lowercased().contains("cancel")
            for elemento in elementos {
                salida.fallos.append(.init(elemento: elemento,
                                           motivo: cancelado ? "Cancelaste la petición de contraseña." : "No se pudo obtener el permiso de administrador.",
                                           necesitaAdmin: true))
            }
            return salida
        }

        let lineas = Self.leerSalida(resultado.salida)
        for elemento in elementos {
            switch lineas[elemento.url.path] {
            case .some(.ok), .some(.ausente):
                salida.enviados.append(elemento)
            case .some(.fallo(let motivo)):
                salida.fallos.append(.init(elemento: elemento, motivo: motivo, necesitaAdmin: false))
            case nil:
                salida.fallos.append(.init(elemento: elemento, motivo: "El script no informó de este elemento.", necesitaAdmin: false))
            }
            if let servicio = elemento.servicio, case .some(.ok) = lineas[elemento.url.path] { salida.apagados.append(servicio.etiqueta) }
        }
        return salida
    }

    enum LineaDeSalida: Equatable {
        case ok, ausente, fallo(String)
    }

    /// El guion que se ejecuta como root. Es texto plano de `sh`: por cada elemento apaga su
    /// servicio (si lo tiene), lo mueve a la Papelera del usuario sin pisar nada y le devuelve
    /// la propiedad al usuario, para que pueda vaciar la Papelera sin contraseña.
    static func guionDeAdministrador(_ elementos: [Elemento], papelera: URL, uid: UInt32, gid: UInt32) -> String {
        var l: [String] = []
        l.append("destino=\(comillas(papelera.path))")
        l.append(#"mover() {"#)
        l.append(#"  origen="$1""#)
        l.append(#"  if [ ! -e "$origen" ] && [ ! -L "$origen" ]; then printf 'AUSENTE\t%s\n' "$origen"; return; fi"#)
        l.append(#"  nombre=$(/usr/bin/basename "$origen"); final="$destino/$nombre"; n=2"#)
        l.append(#"  while [ -e "$final" ] || [ -L "$final" ]; do final="$destino/$nombre $n"; n=$((n+1)); done"#)
        l.append(#"  if fallo=$(/bin/mv "$origen" "$final" 2>&1); then"#)
        l.append(#"    /usr/sbin/chown -R -h \#(uid):\#(gid) "$final" 2>/dev/null"#)
        l.append(#"    printf 'OK\t%s\n' "$origen""#)
        l.append(#"  else"#)
        l.append(#"    printf 'FALLO\t%s\t%s\n' "$origen" "$(printf '%s' "$fallo" | /usr/bin/tr '\n\t' '  ')""#)
        l.append(#"  fi"#)
        l.append(#"}"#)
        for elemento in elementos {
            if let servicio = elemento.servicio, servicio.dominio == .sistema {
                l.append("/bin/launchctl bootout \(comillas("system/" + servicio.etiqueta)) >/dev/null 2>&1")
            }
            l.append("mover \(comillas(elemento.url.path))")
        }
        return l.joined(separator: "\n")
    }

    /// Entre comillas simples, a prueba de espacios y de comillas dentro del nombre.
    static func comillas(_ texto: String) -> String {
        "'" + texto.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// `do shell script … with administrator privileges`, con el guion escapado para AppleScript.
    static func appleScript(_ guion: String, aviso: String) -> String {
        func literal(_ t: String) -> String {
            "\"" + t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "do shell script \(literal(guion)) with prompt \(literal(aviso)) with administrator privileges"
    }

    /// Convierte las líneas `OK\truta`, `AUSENTE\truta` y `FALLO\truta\tmotivo` en un diccionario.
    static func leerSalida(_ salida: String) -> [String: LineaDeSalida] {
        var resultado: [String: LineaDeSalida] = [:]
        // AppleScript devuelve los saltos de línea como retornos de carro.
        for linea in salida.replacingOccurrences(of: "\r", with: "\n").split(separator: "\n") {
            let partes = linea.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard partes.count >= 2 else { continue }
            switch partes[0] {
            case "OK": resultado[partes[1]] = .ok
            case "AUSENTE": resultado[partes[1]] = .ausente
            case "FALLO": resultado[partes[1]] = .fallo(partes.count > 2 ? partes[2] : "No se pudo mover.")
            default: break
            }
        }
        return resultado
    }

    // MARK: Errores y procesos

    static func explicar(_ error: Error) -> String {
        let e = error as NSError
        if esDePermisos(error) {
            return "macOS no me dejó moverlo. Prueba a darle a CleanUninstall «Acceso total al disco» o «Administración de apps» en Ajustes del Sistema."
        }
        if e.domain == NSCocoaErrorDomain, e.code == NSFileNoSuchFileError || e.code == NSFileReadNoSuchFileError {
            return "Ya no estaba."
        }
        return e.localizedDescription
    }

    static func esDePermisos(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain { return e.code == NSFileWriteNoPermissionError || e.code == NSFileReadNoPermissionError }
        if e.domain == NSPOSIXErrorDomain { return e.code == Int(EACCES) || e.code == Int(EPERM) }
        if let origen = e.userInfo[NSUnderlyingErrorKey] as? Error { return esDePermisos(origen) }
        return false
    }

    public static let ejecutarDeVerdad: Ejecutor = { programa, argumentos in
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: programa)
        proceso.arguments = argumentos
        let tuberia = Pipe()
        proceso.standardOutput = tuberia
        proceso.standardError = tuberia
        do { try proceso.run() } catch { return (-1, "\(error)") }
        let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
        proceso.waitUntilExit()
        return (proceso.terminationStatus, String(decoding: datos, as: UTF8.self))
    }
}

// MARK: - Cerrar la app

public enum CerrarApp {
    /// Pide a la app que se cierre y espera hasta `segundos`. `true` si ya no está abierta.
    /// No fuerza nada: si la app tiene un documento sin guardar, será ella quien pregunte.
    public static func cerrar(_ app: AppObjetivo, esperando segundos: Double = 6) async -> Bool {
        let abiertas = NSRunningApplication.runningApplications(withBundleIdentifier: app.identificador)
        guard !abiertas.isEmpty else { return true }
        abiertas.forEach { $0.terminate() }
        let limite = Date().addingTimeInterval(segundos)
        while Date() < limite {
            if abiertas.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return abiertas.allSatisfy(\.isTerminated)
    }
}
