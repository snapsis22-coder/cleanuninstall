import AppKit
import Foundation

/// Busca los restos de una app en las carpetas del catálogo. **Sólo lee**: nunca mueve ni borra.
public struct Buscador: Sendable {
    public let entorno: Entorno

    public init(entorno: Entorno = .real) {
        self.entorno = entorno
    }

    public func buscar(_ app: AppObjetivo, otras: OtrasApps? = nil) async -> Resultado {
        let otras = otras ?? OtrasApps.escanear(sin: app)
        var pesquisa = Pesquisa(app: app, otras: otras, entorno: entorno)
        pesquisa.recorrer()
        var elementos = pesquisa.resultado()

        // Los tamaños tardan (carpetas con miles de archivos): en paralelo y al final.
        let tamaños = await withTaskGroup(of: (Int, Int64).self) { grupo in
            for (indice, elemento) in elementos.enumerated() {
                grupo.addTask { (indice, Tamaño.de(elemento.url)) }
            }
            var resultado: [Int: Int64] = [:]
            for await (indice, tamaño) in grupo { resultado[indice] = tamaño }
            return resultado
        }
        for indice in elementos.indices { elementos[indice].tamaño = tamaños[indice] ?? 0 }

        elementos.sort {
            ($0.categoria, $0.confianza, -$0.tamaño, $0.nombre.lowercased())
                < ($1.categoria, $1.confianza, -$1.tamaño, $1.nombre.lowercased())
        }
        return Resultado(app: app, elementos: elementos, carpetasSinAcceso: pesquisa.sinAcceso,
                         estaAbierta: !NSRunningApplication.runningApplications(withBundleIdentifier: app.identificador).isEmpty)
    }
}

// MARK: - Recorrido

/// El estado de una búsqueda. Se separa de `Buscador` para poder acumular sin pelearse con la
/// concurrencia: vive y muere dentro de una llamada.
private struct Pesquisa {
    let app: AppObjetivo
    let entorno: Entorno
    let clasificador: Clasificador
    let otras: OtrasApps
    let fm = FileManager.default

    private(set) var hallados: [String: Elemento] = [:]
    private(set) var sinAcceso: [URL] = []
    /// Etiquetas (en minúsculas) que ya sabemos que son de la app: sirven para reconocer más.
    private var propiosDeServicio: Set<String> = []

    init(app: AppObjetivo, otras: OtrasApps, entorno: Entorno) {
        self.app = app
        self.otras = otras
        self.entorno = entorno
        self.clasificador = Clasificador(app: app, otras: otras)
    }

    mutating func recorrer() {
        añadir(app.url, .aplicacion, "Aplicación", Clasificador.Veredicto(confianza: .exacta, motivo: "La app que elegiste"))

        let catalogo = Ubicacion.catalogo(en: entorno)
        // Primero todo lo que no es de launchd: los servicios se juzgan después, porque a veces
        // sólo se reconocen por ejecutar algo que ya encontramos.
        for (ubicacion, carpeta) in catalogo {
            switch ubicacion.modo {
            case .servicios: continue
            default: recorrer(ubicacion, en: carpeta)
            }
        }
        // Los servicios se reconocen unos a otros, así que se repasa hasta que no aparezca nada nuevo.
        propiosDeServicio = Set(app.identificadoresPropios.map { $0.lowercased() })
            .union(app.ayudantesPrivilegiados.map { $0.lowercased() })
            .union(app.etiquetasDeServicio.map { $0.lowercased() })
        for _ in 0..<4 {
            let antes = hallados.count + propiosDeServicio.count
            for (ubicacion, carpeta) in catalogo {
                if case .servicios(let dominio) = ubicacion.modo { recorrerServicios(ubicacion, carpeta, dominio) }
            }
            if hallados.count + propiosDeServicio.count == antes { break }
        }
    }

    /// Los hallazgos, sin los que están dentro de otro hallazgo (si se tira la carpeta, sobra el hijo).
    func resultado() -> [Elemento] {
        let todos = Array(hallados.values)
        return todos.filter { elemento in
            let ruta = elemento.url.standardizedFileURL.path
            return !todos.contains { otro in
                let rutaOtro = otro.url.standardizedFileURL.path
                return rutaOtro != ruta && ruta.hasPrefix(rutaOtro + "/")
            }
        }
    }

    // MARK: Carpetas normales

    private mutating func recorrer(_ ubicacion: Ubicacion, en carpeta: URL) {
        guard let hijos = listarAnotando(carpeta) else { return }
        for hijo in hijos {
            let nombre = hijo.lastPathComponent
            switch ubicacion.modo {
            case .archivos:
                if let v = clasificador.clasificar(nombre) { añadir(hijo, ubicacion, v) }

            case .anidable:
                if let v = clasificador.clasificar(nombre) {
                    añadir(hijo, ubicacion, v)
                } else if clasificador.esCarpetaDelFabricante(nombre) {
                    // `Application Support/Google/Chrome`: se mira dentro de la carpeta del
                    // fabricante y se toma sólo lo que es de la app, nunca la carpeta entera.
                    for nieto in listar(hijo) ?? [] {
                        guard let v = clasificador.clasificar(nieto.lastPathComponent) else { continue }
                        añadir(nieto, ubicacion, Clasificador.Veredicto(
                            confianza: v.confianza, motivo: "\(v.motivo) (dentro de la carpeta «\(nombre)»)"))
                    }
                }

            case .grupos:
                recorrerGrupo(hijo, ubicacion)

            case .complementos:
                if let v = clasificador.clasificar(nombre) {
                    añadir(hijo, ubicacion, v)
                } else if let id = Plist.leer(hijo.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String,
                          let v = clasificador.clasificar(id), v.confianza == .exacta {
                    añadir(hijo, ubicacion, Clasificador.Veredicto(confianza: .exacta, motivo: "Su identificador es \(id)"))
                }

            case .ayudantes:
                let minuscula = nombre.lowercased()
                let declarados = Set(app.ayudantesPrivilegiados.map { $0.lowercased() })
                if declarados.contains(minuscula) {
                    añadir(hijo, ubicacion, Clasificador.Veredicto(confianza: .exacta, motivo: "La app declara este ayudante"))
                } else if let v = clasificador.clasificar(nombre) {
                    añadir(hijo, ubicacion, v)
                }

            case .informes:
                if let v = clasificador.clasificarInforme(nombre) { añadir(hijo, ubicacion, v) }

            case .servicios:
                break
            }
        }
    }

    /// `Group Containers`: la app declara sus grupos en los permisos. Si otra app instalada
    /// declara el mismo, no es sólo nuestro y se deja sin marcar.
    private mutating func recorrerGrupo(_ hijo: URL, _ ubicacion: Ubicacion) {
        let nombre = hijo.lastPathComponent
        let minuscula = nombre.lowercased()
        let declarados = Set(app.grupos.map { $0.lowercased() })

        var veredicto: Clasificador.Veredicto?
        if declarados.contains(minuscula) {
            veredicto = .init(confianza: .exacta, motivo: "La app declara este grupo de datos")
        } else if let equipo = app.equipo?.lowercased(), minuscula.hasPrefix(equipo + "."),
                  let v = clasificador.clasificar(String(nombre.dropFirst(equipo.count + 1))), v.confianza == .exacta {
            veredicto = .init(confianza: .exacta, motivo: "Lleva el equipo y el identificador de la app")
        } else {
            veredicto = clasificador.clasificar(nombre)
        }
        guard var v = veredicto else { return }

        var nota: String?
        if let usuarios = otras.usuariosDeGrupo[minuscula], !usuarios.isEmpty {
            nota = "También la usa: " + usuarios.sorted().joined(separator: ", ")
            v = .init(confianza: .dudosa, motivo: "Carpeta compartida con otras apps")
        }
        añadir(hijo, ubicacion, v, nota: nota)
    }

    // MARK: Servicios de launchd

    /// Un `.plist` de `LaunchAgents`/`LaunchDaemons` es de la app si:
    ///   · su etiqueta es un identificador (o un servicio) de la app, **o**
    ///   · lo que ejecuta está dentro de la app, **o**
    ///   · declara estar asociado a la app, **o**
    ///   · lo que ejecuta está dentro de algo que ya sabemos que es de la app.
    /// Las dos primeras son lo que evita llevarse un demonio de otra app por un nombre parecido.
    private mutating func recorrerServicios(_ ubicacion: Ubicacion, _ carpeta: URL, _ dominio: ServicioLaunchd.Dominio) {
        guard let archivos = listarAnotando(carpeta) else { return }
        let rutaDeLaApp = app.url.standardizedFileURL.path

        for archivo in archivos where archivo.pathExtension == "plist" {
            guard let datos = Plist.leer(archivo) else { continue }
            let etiqueta = (datos["Label"] as? String) ?? archivo.deletingPathExtension().lastPathComponent
            let ejecutable = (datos["Program"] as? String) ?? (datos["ProgramArguments"] as? [String])?.first
            let asociados = Self.textos(datos["AssociatedBundleIdentifiers"]).map { $0.lowercased() }

            // Se juntan todas las pistas y gana la más segura: un demonio puede llevar un nombre
            // dudoso y a la vez ejecutar algo que sí es de la app.
            var pistas: [Clasificador.Veredicto] = []
            if propiosDeServicio.contains(etiqueta.lowercased()) {
                pistas.append(.init(confianza: .exacta, motivo: "La app declara este servicio"))
            }
            if let ejecutable, enRuta(ejecutable, dentroDe: rutaDeLaApp) {
                pistas.append(.init(confianza: .exacta, motivo: "Ejecuta algo que está dentro de la app"))
            }
            if asociados.contains(where: propiosDeServicio.contains) {
                pistas.append(.init(confianza: .exacta, motivo: "Está asociado a la app o a uno de sus servicios"))
            }
            if let v = clasificador.clasificar(archivo.lastPathComponent) ?? clasificador.clasificar(etiqueta) {
                pistas.append(v)
            }
            if let ejecutable, let padre = hallazgoQueContiene(ejecutable) {
                pistas.append(.init(confianza: padre.confianza == .exacta ? .exacta : .porNombre,
                                    motivo: "Ejecuta algo de «\(padre.url.lastPathComponent)»"))
            }
            guard let v = pistas.min(by: { $0.confianza < $1.confianza }) else { continue }

            añadir(archivo, ubicacion, v, servicio: ServicioLaunchd(etiqueta: etiqueta, dominio: dominio))
            // Los servicios que ya sabemos de la app sirven de pista para reconocer a sus hermanos
            // (el demonio del actualizador se asocia al agente principal, no a la app).
            // Sólo los seguros: si un «por nombre» se sirviera de pista a sí mismo, se ascendería solo.
            if v.confianza == .exacta { propiosDeServicio.insert(etiqueta.lowercased()) }

            // Si el servicio ejecuta un ayudante privilegiado, ése también es de la app.
            if let ejecutable, ejecutable.contains("/Library/PrivilegedHelperTools/") {
                let ayudante = rutaReal(ejecutable)
                if fm.fileExists(atPath: ayudante.path) {
                    añadir(ayudante, .servicios, "Ayudante privilegiado",
                           .init(confianza: v.confianza, motivo: "Lo ejecuta el servicio «\(etiqueta)»"))
                }
            }
        }
    }

    /// Una ruta absoluta del sistema, llevada a la raíz de este entorno (en pruebas, la de mentira).
    private func rutaReal(_ absoluta: String) -> URL {
        entorno.raiz.path == "/" ? URL(fileURLWithPath: absoluta).standardizedFileURL
            : entorno.raiz.appendingPathComponent(absoluta).standardizedFileURL
    }

    // MARK: Utilidades

    private func listar(_ carpeta: URL) -> [URL]? {
        var esCarpeta: ObjCBool = false
        guard fm.fileExists(atPath: carpeta.path, isDirectory: &esCarpeta), esCarpeta.boolValue else { return nil }
        do {
            return try fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil, options: [])
        } catch {
            return nil
        }
    }

    private mutating func listarAnotando(_ carpeta: URL) -> [URL]? {
        if let hijos = listar(carpeta) { return hijos }
        // Existe pero no se puede leer: casi siempre falta «Acceso total al disco».
        if fm.fileExists(atPath: carpeta.path), !fm.isReadableFile(atPath: carpeta.path) { sinAcceso.append(carpeta) }
        return nil
    }

    private mutating func añadir(_ url: URL, _ ubicacion: Ubicacion, _ v: Clasificador.Veredicto,
                                 servicio: ServicioLaunchd? = nil, nota: String? = nil) {
        añadir(url, ubicacion.categoria, ubicacion.tipo, v, servicio: servicio, nota: nota)
    }

    private mutating func añadir(_ url: URL, _ categoria: Categoria, _ tipo: String, _ v: Clasificador.Veredicto,
                                 servicio: ServicioLaunchd? = nil, nota: String? = nil) {
        let url = url.standardizedFileURL
        // Si ya estaba, gana la lectura más segura.
        if let previo = hallados[url.path], previo.confianza <= v.confianza { return }
        hallados[url.path] = Elemento(
            url: url, categoria: categoria, tipo: tipo, confianza: v.confianza, motivo: v.motivo,
            requiereAdmin: necesitaAdmin(url), servicio: servicio, nota: nota)
    }

    /// ¿Puede el usuario mandar esto a la Papelera sin contraseña?
    private func necesitaAdmin(_ url: URL) -> Bool {
        guard fm.isDeletableFile(atPath: url.path) else { return true }
        // En carpetas con «sticky bit» (/Library/Caches) sólo el dueño puede quitar lo suyo.
        let padre = url.deletingLastPathComponent().path
        guard let atributosPadre = try? fm.attributesOfItem(atPath: padre),
              let permisos = (atributosPadre[.posixPermissions] as? NSNumber)?.uint16Value,
              permisos & 0o1000 != 0,
              let atributos = try? fm.attributesOfItem(atPath: url.path),
              let dueño = (atributos[.ownerAccountID] as? NSNumber)?.uint32Value else { return false }
        return dueño != entorno.uid
    }

    private func hallazgoQueContiene(_ ejecutable: String) -> Elemento? {
        hallados.values.first { enRuta(ejecutable, dentroDe: $0.url.standardizedFileURL.path) && $0.confianza != .dudosa }
    }

    private func enRuta(_ ruta: String, dentroDe carpeta: String) -> Bool {
        let limpia = URL(fileURLWithPath: ruta).standardizedFileURL.path
        return limpia.hasPrefix(carpeta + "/")
    }

    private static func textos(_ valor: Any?) -> [String] {
        if let uno = valor as? String { return [uno] }
        return (valor as? [String]) ?? []
    }
}
