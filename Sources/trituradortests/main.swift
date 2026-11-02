import Foundation
@testable import TrituradorKit

/// Arnés de pruebas propio, igual que en SubFix: `swift run trituradortests`.
///
/// Todo se prueba contra un «sistema de mentira» en una carpeta temporal (un Mac con su
/// /Library, su ~/Library y unas cuantas apps). Nada toca el disco de verdad.
var pasadas = 0, falladas = 0

func probar(_ nombre: String, _ cuerpo: () throws -> Bool) {
    do {
        if try cuerpo() { pasadas += 1; print("  ✅ \(nombre)") }
        else { falladas += 1; print("  ❌ \(nombre)") }
    } catch {
        falladas += 1; print("  ❌ \(nombre) — \(error)")
    }
}

func probarEsperando(_ nombre: String, _ cuerpo: () async throws -> Bool) async {
    do {
        if try await cuerpo() { pasadas += 1; print("  ✅ \(nombre)") }
        else { falladas += 1; print("  ❌ \(nombre)") }
    } catch {
        falladas += 1; print("  ❌ \(nombre) — \(error)")
    }
}

// MARK: - Modo «mirar»

/// `trituradortests --buscar /Applications/Algo.app` enseña qué encontraría Triturador en ESTE Mac.
/// Sólo lee: no mueve ni borra nada.
if let i = CommandLine.arguments.firstIndex(of: "--buscar"), i + 1 < CommandLine.arguments.count {
    let app = try AppObjetivo.leer(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    print("\(app.nombre)  \(app.identificador)  equipo=\(app.equipo ?? "-")  grupos=\(app.grupos.sorted())")
    if let motivo = app.motivoDeProteccion { print("PROTEGIDA: \(motivo)"); exit(0) }
    let inicio = Date()
    let r = await Buscador().buscar(app)
    func mb(_ b: Int64) -> String { String(format: "%.1f MB", Double(b) / 1_000_000) }
    var categoria: Categoria?
    for e in r.elementos {
        if e.categoria != categoria { categoria = e.categoria; print("\n[\(e.categoria.titulo)]") }
        let marca = e.marcadoDeEntrada ? "☑︎" : "☐"
        print("  \(marca) \(e.confianza.etiqueta.padding(toLength: 10, withPad: " ", startingAt: 0)) \(mb(e.tamaño).padding(toLength: 10, withPad: " ", startingAt: 0)) \(e.url.path)\(e.requiereAdmin ? "   [admin]" : "")\(e.servicio.map { "   [servicio \($0.etiqueta)]" } ?? "")")
        print("       ↳ \(e.motivo)\(e.nota.map { " · \($0)" } ?? "")")
    }
    print("\nTotal \(mb(r.tamañoTotal)) en \(r.elementos.count) elementos · \(String(format: "%.2f", Date().timeIntervalSince(inicio))) s")
    if !r.carpetasSinAcceso.isEmpty { print("Sin acceso a: \(r.carpetasSinAcceso.map(\.path))") }
    if r.estaAbierta { print("(la app está abierta)") }
    exit(0)
}

// MARK: - Modo «prueba real»

/// `trituradortests --prueba-real` hace de verdad, en ESTE Mac, el recorrido completo con una app
/// inventada: la crea, le carga un agente de launchd que sigue vivo, la busca y la tritura.
/// Sólo toca archivos con el nombre `com.snapsis.zapprueba…`, creados aquí mismo.
if CommandLine.arguments.contains("--prueba-real") {
    let fm = FileManager.default
    let id = "com.snapsis.zapprueba\(Int.random(in: 1000...9999))"
    let casa = fm.homeDirectoryForCurrentUser
    let uid = getuid()
    func sh(_ programa: String, _ args: [String]) -> (Int32, String) { Papelera.ejecutarDeVerdad(programa, args) }

    let app = fm.homeDirectoryForCurrentUser.appendingPathComponent("Developer/Triturador/.build/prueba-real/ZapPrueba.app")
    try? fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    precondition((["CFBundleIdentifier": id, "CFBundleName": "ZapPrueba"] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
    let prefs = casa.appendingPathComponent("Library/Preferences/\(id).plist")
    let cache = casa.appendingPathComponent("Library/Caches/\(id)")
    let agente = casa.appendingPathComponent("Library/LaunchAgents/\(id).plist")
    try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    try "x".write(to: cache.appendingPathComponent("a.bin"), atomically: true, encoding: .utf8)
    precondition((["a": 1] as NSDictionary).write(to: prefs, atomically: true))
    precondition((["Label": id, "ProgramArguments": ["/bin/sleep", "600"], "RunAtLoad": true] as NSDictionary).write(to: agente, atomically: true))
    print("bootstrap:", sh("/bin/launchctl", ["bootstrap", "gui/\(uid)", agente.path]).0)
    func vivo() -> Bool { sh("/bin/launchctl", ["print", "gui/\(uid)/\(id)"]).0 == 0 }
    print("agente cargado antes:", vivo())

    let objetivo = try AppObjetivo.leer(app)
    let r = await Buscador().buscar(objetivo, otras: .ninguna)
    for e in r.elementos { print("  ", e.marcadoDeEntrada ? "☑︎" : "☐", e.confianza.etiqueta, e.url.path.replacingOccurrences(of: casa.path, with: "~")) }
    let informe = await Papelera().triturar(r.elementos.filter(\.marcadoDeEntrada), de: objetivo, conAdmin: false)
    print("enviados:", informe.enviados.count, "fallos:", informe.fallos.map(\.motivo), "apagados:", informe.serviciosApagados)
    print("agente cargado después:", vivo())
    for u in [app, prefs, cache, agente] { print("  sigue en su sitio:", fm.fileExists(atPath: u.path), u.lastPathComponent) }
    print("en la Papelera:", ((try? fm.contentsOfDirectory(atPath: casa.appendingPathComponent(".Trash").path)) ?? []).filter { $0.contains("zapprueba") || $0 == "ZapPrueba.app" }.sorted())
    exit(0)
}

// MARK: - El sistema de mentira

let fm = FileManager.default
let temporal = fm.temporaryDirectory.appendingPathComponent("trituradortests-\(UUID().uuidString)").standardizedFileURL
defer { try? fm.removeItem(at: temporal) }

let raiz = temporal.appendingPathComponent("disco")
let inicio = raiz.appendingPathComponent("Users/prueba")
let entorno = Entorno(inicio: inicio, raiz: raiz, uid: getuid(), gid: getgid())

func ruta(_ relativa: String) -> URL { raiz.appendingPathComponent(relativa) }
func casa(_ relativa: String) -> URL { inicio.appendingPathComponent(relativa) }

func carpeta(_ url: URL) { try! fm.createDirectory(at: url, withIntermediateDirectories: true) }
func archivo(_ url: URL, _ texto: String = "x") {
    carpeta(url.deletingLastPathComponent())
    try! texto.write(to: url, atomically: true, encoding: .utf8)
}
func plist(_ url: URL, _ datos: [String: Any]) {
    carpeta(url.deletingLastPathComponent())
    precondition((datos as NSDictionary).write(to: url, atomically: true))
}

/// Una app falsa con su Info.plist.
@discardableResult
func crearApp(_ nombre: String, id: String, en carpetaDeApps: String = "Applications",
              extra: [String: Any] = [:]) -> URL {
    let app = ruta("\(carpetaDeApps)/\(nombre).app")
    var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": nombre,
                               "CFBundleShortVersionString": "1.0", "CFBundleExecutable": nombre]
    info.merge(extra) { $1 }
    plist(app.appendingPathComponent("Contents/Info.plist"), info)
    archivo(app.appendingPathComponent("Contents/MacOS/\(nombre)"), "binario")
    return app
}

// Foo (la app que vamos a quitar), con una extensión y un ayudante privilegiado.
let fooURL = crearApp("Foo", id: "com.acme.Foo", extra: ["SMPrivilegedExecutables": ["com.acme.Foo.Helper": "identifier x"]])
plist(fooURL.appendingPathComponent("Contents/PlugIns/FooWidget.appex/Contents/Info.plist"),
      ["CFBundleIdentifier": "com.acme.Foo.Widget"])
archivo(fooURL.appendingPathComponent("Contents/MacOS/updater"), "updater")
// Sparkle dentro de Frameworks: NO debe contar como pieza de Foo.
plist(fooURL.appendingPathComponent("Contents/Frameworks/Sparkle.framework/Resources/Autoupdate.app/Contents/Info.plist"),
      ["CFBundleIdentifier": "org.sparkle-project.Sparkle.Autoupdate"])

// Otra app del mismo fabricante cuyo id empieza igual que el de Foo (el caso Chrome / Canary).
crearApp("Foo Beta", id: "com.acme.Foo.beta")
// Y una copia de Foo en otro sitio: no cuenta como «otra app».
crearApp("Foo", id: "com.acme.Foo", en: "Users/prueba/Downloads")

// — Restos de Foo en ~/Library —
archivo(casa("Library/Preferences/com.acme.Foo.plist"))
archivo(casa("Library/Preferences/com.acme.Foo.Widget.plist"))
archivo(casa("Library/Preferences/com.acme.Foo.beta.plist"))                 // de Foo Beta
archivo(casa("Library/Preferences/com.acme.FooOther.plist"))                 // otro id que sólo se parece
archivo(casa("Library/Preferences/com.acme.Foo.misterio.plist"))             // dudoso
archivo(casa("Library/Preferences/com.apple.Foo.plist"))                     // de Apple
archivo(casa("Library/Preferences/ByHost/com.acme.Foo.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist"))
archivo(casa("Library/Caches/com.acme.Foo/datos.bin"), String(repeating: "z", count: 5000))
archivo(casa("Library/Caches/com.acme.Foo.beta/otro.bin"))
archivo(casa("Library/Containers/com.acme.Foo/Data/uno.txt"))
archivo(casa("Library/Containers/com.acme.Foo.Widget/Data/dos.txt"))
archivo(casa("Library/Saved Application State/com.acme.Foo.savedState/windows.plist"))
archivo(casa("Library/Application Support/Foo/config.json"))
archivo(casa("Library/Application Support/Foo/Caches/dentro.bin"))           // dentro de lo anterior
archivo(casa("Library/Application Support/Acme/Foo/datos.db"))               // dentro de la carpeta del fabricante
archivo(casa("Library/Application Support/Acme/Bar/datos.db"))               // otra app del fabricante
archivo(casa("Library/Application Support/Notes/nota.db"))                   // ajeno
archivo(casa("Library/Logs/DiagnosticReports/Foo_2026-11-02-100000_mac.ips"))
archivo(casa("Library/Logs/DiagnosticReports/Bar_2026-11-02-100000_mac.ips"))
archivo(casa("Library/Group Containers/ACME123.shared/x.db"))                // grupo propio
archivo(casa("Library/Group Containers/ACME123.compartido/x.db"))            // grupo compartido con otra app
archivo(casa("Library/Group Containers/OTRO999.ajeno/x.db"))
archivo(casa("Library/Audio/Plug-Ins/VST3/Foo.vst3/Contents/x"))
plist(casa("Library/Audio/Plug-Ins/Components/Raro.component/Contents/Info.plist"), ["CFBundleIdentifier": "com.acme.Foo.Widget"])

// — Restos de Foo en /Library —
plist(ruta("Library/LaunchDaemons/com.acme.Foo.Helper.plist"),
      ["Label": "com.acme.Foo.Helper", "Program": "/Library/PrivilegedHelperTools/com.acme.Foo.Helper"])
archivo(ruta("Library/PrivilegedHelperTools/com.acme.Foo.Helper"), "helper")
plist(ruta("Library/LaunchDaemons/mantenimiento.plist"),                      // otro nombre, pero ejecuta algo de Foo
      ["Label": "mantenimiento", "ProgramArguments": [fooURL.path + "/Contents/MacOS/updater", "--silencioso"]])
plist(ruta("Library/LaunchAgents/agente.plist"),                              // se reconoce por AssociatedBundleIdentifiers
      ["Label": "agente.extraño", "Program": "/opt/lo-que-sea", "AssociatedBundleIdentifiers": ["com.acme.Foo"]])
plist(ruta("Library/LaunchAgents/com.acme.Foo.beta.agent.plist"),             // de Foo Beta
      ["Label": "com.acme.Foo.beta.agent", "Program": "/opt/beta"])
plist(ruta("Library/LaunchDaemons/com.otro.cosa.plist"),                      // de nadie conocido
      ["Label": "com.otro.cosa", "Program": "/opt/otro/cosa"])
plist(casa("Library/LaunchAgents/sync.plist"),                                // ejecuta algo de Application Support/Foo
      ["Label": "sync", "Program": casa("Library/Application Support/Foo/sincroniza").path])
plist(ruta("Library/LaunchDaemons/foo.updater.plist"),                         // se asocia al AGENTE de Foo, no a la app (caso Logi Options+)
      ["Label": "foo.updater", "Program": "/opt/foo-updater", "AssociatedBundleIdentifiers": ["agente.extraño"]])
archivo(casa("Library/Application Support/AcmeStuff/Foo/x.db"))                // carpeta del fabricante con otro nombre (caso Logitech.localized)
archivo(ruta("private/var/db/receipts/com.acme.Foo.plist"))
archivo(ruta("private/var/db/receipts/com.acme.Foo.bom"))
archivo(ruta("private/var/db/receipts/com.acme.Foo.beta.plist"))

// Lo que NO es de Foo y no debe aparecer jamás.
archivo(casa("Documents/Foo/mis-cosas.txt"))
archivo(casa("Desktop/Foo.txt"))

// La app tal como la leería la interfaz (sin firmar: sin equipo ni grupos), y con grupos para probar `Group Containers`.
let foo = try AppObjetivo.leer(fooURL, propioIdentificador: "com.snapsis.triturador")
let fooConGrupos = AppObjetivo(
    url: foo.url, nombre: foo.nombre, identificador: foo.identificador, version: foo.version,
    nombresPosibles: foo.nombresPosibles, identificadoresPropios: foo.identificadoresPropios,
    ayudantesPrivilegiados: foo.ayudantesPrivilegiados, etiquetasDeServicio: foo.etiquetasDeServicio,
    grupos: ["ACME123.shared", "ACME123.compartido"], equipo: "ACME123", motivoDeProteccion: nil)

let otras = OtrasApps.escanear(sin: foo, en: [ruta("Applications"), casa("Downloads")])

// MARK: - Lectura de la app

print("\n▸ Lectura de la app")

probar("lee identificador, nombre y versión") {
    foo.identificador == "com.acme.Foo" && foo.nombre == "Foo" && foo.version == "1.0"
}
probar("reconoce la extensión interna como pieza propia") {
    foo.identificadoresPropios.contains("com.acme.Foo.Widget")
}
probar("NO toma como propio lo que hay en Frameworks (Sparkle)") {
    !foo.identificadoresPropios.contains("org.sparkle-project.Sparkle.Autoupdate")
}
probar("lee los ayudantes privilegiados declarados") {
    foo.ayudantesPrivilegiados.contains("com.acme.Foo.Helper")
}
probar("rechaza algo que no es .app") {
    do { _ = try AppObjetivo.leer(casa("Documents/Foo")); return false } catch { return true }
}
probar("protege las apps del sistema (/System)") {
    (try? AppObjetivo.leer(URL(fileURLWithPath: "/System/Applications/Calculator.app")))?.estaProtegida == true
}
probar("protege Safari (firmada por Apple como sistema)") {
    guard fm.fileExists(atPath: "/Applications/Safari.app") else { return true }   // en macOS nuevos vive en un cryptex
    return (try? AppObjetivo.leer(URL(fileURLWithPath: "/Applications/Safari.app")))?.estaProtegida == true
}
probar("no se deja triturar a sí mismo") {
    (try? AppObjetivo.leer(fooURL, propioIdentificador: "com.acme.Foo"))?.estaProtegida == true
}
probar("las otras apps no incluyen una copia de la misma app") {
    otras.identificadores.contains("com.acme.foo.beta") && !otras.identificadores.contains("com.acme.foo")
}

// MARK: - Clasificador

print("\n▸ Clasificador")

let clasificador = Clasificador(app: foo, otras: otras)

probar("identificador exacto → segura") { clasificador.clasificar("com.acme.Foo")?.confianza == .exacta }
probar("insensible a mayúsculas (APFS) → segura") { clasificador.clasificar("COM.ACME.FOO.plist")?.confianza == .exacta }
probar("sufijos que añade macOS → seguros") {
    ["com.acme.Foo.plist", "com.acme.Foo.savedState", "com.acme.Foo.binarycookies", "com.acme.Foo.ShipIt"]
        .allSatisfy { clasificador.clasificar($0)?.confianza == .exacta }
}
probar("preferencias ByHost con UUID → seguras") {
    clasificador.clasificar("com.acme.Foo.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")?.confianza == .exacta
}
probar("id de una pieza propia (Widget) → segura") { clasificador.clasificar("com.acme.Foo.Widget.plist")?.confianza == .exacta }
probar("id de otra app que empieza igual (Foo.beta) → se descarta") { clasificador.clasificar("com.acme.Foo.beta.plist") == nil }
probar("empieza por el id pero es desconocido → dudosa") { clasificador.clasificar("com.acme.Foo.misterio.plist")?.confianza == .dudosa }
probar("un id que sólo se parece (FooOther) → nada") { clasificador.clasificar("com.acme.FooOther.plist") == nil }
probar("nada de com.apple.*") { clasificador.clasificar("com.apple.Foo.plist") == nil }
probar("mismo nombre que la app → por nombre") { clasificador.clasificar("Foo")?.confianza == .porNombre }
probar("por nombre ignora .vst3 / .plist") {
    clasificador.clasificar("Foo.vst3")?.confianza == .porNombre && clasificador.clasificar("Foo.plist")?.confianza == .porNombre
}
probar("un nombre que contiene el de la app pero no es igual → nada") { clasificador.clasificar("Foo Fighters") == nil }
probar("nombres genéricos no cuentan") {
    let generica = AppObjetivo(url: foo.url, nombre: "Cache", identificador: "com.x.cache", version: nil,
                               nombresPosibles: ["Cache"], identificadoresPropios: ["com.x.cache"],
                               ayudantesPrivilegiados: [], etiquetasDeServicio: [], grupos: [], equipo: nil,
                               motivoDeProteccion: nil)
    return Clasificador(app: generica, otras: .ninguna).clasificar("Caches") == nil
        && Clasificador(app: generica, otras: .ninguna).clasificar("Cache") == nil
}
probar("el fabricante sale del segundo trozo del id") {
    clasificador.fabricante == "acme"
        && Clasificador(app: foo, otras: .ninguna).fabricante == "acme"
}
probar("informes de fallo: Nombre_… con extensión conocida") {
    clasificador.clasificarInforme("Foo_2026-11-02-100000_mac.ips") != nil
        && clasificador.clasificarInforme("Bar_2026-11-02-100000_mac.ips") == nil
        && clasificador.clasificarInforme("Foo_notas.txt") == nil
}

// MARK: - Búsqueda

print("\n▸ Búsqueda")

let buscador = Buscador(entorno: entorno)
let resultado = await buscador.buscar(fooConGrupos, otras: otras)
let porRuta = Dictionary(uniqueKeysWithValues: resultado.elementos.map { ($0.url.path, $0) })

func hay(_ url: URL) -> Bool { porRuta[url.standardizedFileURL.path] != nil }
func confianza(_ url: URL) -> Confianza? { porRuta[url.standardizedFileURL.path]?.confianza }

probar("incluye la app, segura") { confianza(fooURL) == .exacta && porRuta[fooURL.path]?.categoria == .aplicacion }
probar("preferencias, caché, contenedor y estado guardado") {
    [casa("Library/Preferences/com.acme.Foo.plist"), casa("Library/Preferences/com.acme.Foo.Widget.plist"),
     casa("Library/Caches/com.acme.Foo"), casa("Library/Containers/com.acme.Foo"),
     casa("Library/Containers/com.acme.Foo.Widget"), casa("Library/Saved Application State/com.acme.Foo.savedState"),
     casa("Library/Preferences/ByHost/com.acme.Foo.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")]
        .allSatisfy { confianza($0) == .exacta }
}
probar("NO se lleva lo de Foo Beta") {
    !hay(casa("Library/Preferences/com.acme.Foo.beta.plist")) && !hay(casa("Library/Caches/com.acme.Foo.beta"))
        && !hay(ruta("Library/LaunchAgents/com.acme.Foo.beta.agent.plist")) && !hay(ruta("private/var/db/receipts/com.acme.Foo.beta.plist"))
}
probar("lo dudoso aparece, pero como dudoso") { confianza(casa("Library/Preferences/com.acme.Foo.misterio.plist")) == .dudosa }
probar("lo que sólo se parece (FooOther) no aparece") { !hay(casa("Library/Preferences/com.acme.FooOther.plist")) }
probar("lo de Apple no aparece") { !hay(casa("Library/Preferences/com.apple.Foo.plist")) && !hay(casa("Library/Application Support/Notes")) }
probar("carpeta por nombre en Application Support → por nombre") { confianza(casa("Library/Application Support/Foo")) == .porNombre }
probar("carpeta del fabricante: toma sólo Acme/Foo, no Acme ni Acme/Bar") {
    confianza(casa("Library/Application Support/Acme/Foo")) == .porNombre
        && !hay(casa("Library/Application Support/Acme")) && !hay(casa("Library/Application Support/Acme/Bar"))
}
probar("no repite lo que está dentro de otro hallazgo") { !hay(casa("Library/Application Support/Foo/Caches")) }
probar("informes de fallo de Foo sí, los de Bar no") {
    hay(casa("Library/Logs/DiagnosticReports/Foo_2026-11-02-100000_mac.ips"))
        && !hay(casa("Library/Logs/DiagnosticReports/Bar_2026-11-02-100000_mac.ips"))
}
await probarEsperando("grupo declarado por la app → segura; el compartido con otra app → dudosa con nota") {
    // «compartido» lo declara también Foo Beta (simulado en OtrasApps).
    let conCompartido = OtrasApps(identificadores: otras.identificadores,
                                  usuariosDeGrupo: ["ACME123.compartido": ["Foo Beta"]])
    let r = await buscador.buscar(fooConGrupos, otras: conCompartido)
    let propio = r.elementos.first { $0.url.lastPathComponent == "ACME123.shared" }
    let comun = r.elementos.first { $0.url.lastPathComponent == "ACME123.compartido" }
    return propio?.confianza == .exacta && comun?.confianza == .dudosa && comun?.nota?.contains("Foo Beta") == true
        && !r.elementos.contains { $0.url.lastPathComponent == "OTRO999.ajeno" }
}
probar("complemento por nombre y por el id de su Info.plist") {
    confianza(casa("Library/Audio/Plug-Ins/VST3/Foo.vst3")) == .porNombre
        && confianza(casa("Library/Audio/Plug-Ins/Components/Raro.component")) == .exacta
}
probar("recibos de instalación exactos") {
    confianza(ruta("private/var/db/receipts/com.acme.Foo.plist")) == .exacta && confianza(ruta("private/var/db/receipts/com.acme.Foo.bom")) == .exacta
}
probar("NUNCA toca Documentos ni el Escritorio") {
    !hay(casa("Documents/Foo")) && !hay(casa("Desktop/Foo.txt"))
        && !resultado.elementos.contains { $0.url.path.contains("/Documents/") || $0.url.path.contains("/Desktop/") }
}
probar("calcula tamaños") { (porRuta[casa("Library/Caches/com.acme.Foo").path]?.tamaño ?? 0) >= 5000 && resultado.tamañoTotal > 0 }
probar("ordena por categoría: la app primero") { resultado.elementos.first?.categoria == .aplicacion }

print("\n▸ Servicios de launchd")

probar("demonio que la app declara (SMJobBless) → seguro, con su servicio") {
    let e = porRuta[ruta("Library/LaunchDaemons/com.acme.Foo.Helper.plist").path]
    return e?.confianza == .exacta && e?.servicio == ServicioLaunchd(etiqueta: "com.acme.Foo.Helper", dominio: .sistema)
}
probar("el ayudante privilegiado que ejecuta ese demonio también aparece") {
    confianza(ruta("Library/PrivilegedHelperTools/com.acme.Foo.Helper")) == .exacta
}
probar("demonio con OTRO nombre pero que ejecuta algo dentro de la app → seguro") {
    let e = porRuta[ruta("Library/LaunchDaemons/mantenimiento.plist").path]
    return e?.confianza == .exacta && e?.motivo.contains("dentro de la app") == true
}
probar("agente asociado a la app (AssociatedBundleIdentifiers) → seguro, de dominio usuario") {
    let e = porRuta[ruta("Library/LaunchAgents/agente.plist").path]
    return e?.confianza == .exacta && e?.servicio?.dominio == .usuario && e?.servicio?.etiqueta == "agente.extraño"
}
probar("agente que ejecuta algo de una carpeta hallada → lo hereda") {
    let e = porRuta[casa("Library/LaunchAgents/sync.plist").path]
    return e != nil && e?.confianza == .porNombre
}
probar("demonio hermano: se asocia a un servicio ya reconocido → seguro (caso Logi Options+)") {
    confianza(ruta("Library/LaunchDaemons/foo.updater.plist")) == .exacta
}
probar("un servicio «por nombre» no se asciende solo a seguro en la segunda pasada") {
    confianza(casa("Library/LaunchAgents/sync.plist")) == .porNombre
}
probar("carpeta del fabricante con otro nombre (AcmeStuff/Foo)") {
    confianza(casa("Library/Application Support/AcmeStuff/Foo")) == .porNombre
}
probar("demonio de nadie conocido no aparece") { !hay(ruta("Library/LaunchDaemons/com.otro.cosa.plist")) }

// MARK: - Guardia

print("\n▸ Guardia")

func elemento(_ url: URL, _ categoria: Categoria = .datos) -> Elemento {
    Elemento(url: url, categoria: categoria, tipo: "t", confianza: .exacta, motivo: "m", requiereAdmin: false)
}

probar("deja pasar lo que está dentro de una carpeta del catálogo") {
    Guardia.rechazo(elemento(casa("Library/Preferences/com.acme.Foo.plist")), app: foo, entorno: entorno) == nil
}
probar("deja pasar la app") { Guardia.rechazo(elemento(fooURL, .aplicacion), app: foo, entorno: entorno) == nil }
probar("rechaza una carpeta del catálogo entera") {
    Guardia.rechazo(elemento(casa("Library/Caches")), app: foo, entorno: entorno) != nil
        && Guardia.rechazo(elemento(casa("Library")), app: foo, entorno: entorno) != nil
}
probar("rechaza Documentos y la carpeta personal") {
    Guardia.rechazo(elemento(casa("Documents/Foo")), app: foo, entorno: entorno) != nil
        && Guardia.rechazo(elemento(inicio), app: foo, entorno: entorno) != nil
}
probar("rechaza rutas con ..") {
    Guardia.rechazo(elemento(URL(fileURLWithPath: casa("Library/Caches").path + "/../../Documents/Foo")), app: foo, entorno: entorno) != nil
}
probar("rechaza zonas del sistema") {
    Guardia.rechazo(elemento(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")), app: foo, entorno: Entorno.real) != nil
}
probar("rechaza lo de Apple si la app no es de Apple") {
    Guardia.rechazo(elemento(casa("Library/Preferences/com.apple.dock.plist")), app: foo, entorno: entorno) != nil
}
probar("rechaza todo si la app está protegida") {
    let protegida = AppObjetivo(url: foo.url, nombre: "X", identificador: "com.apple.x", version: nil, nombresPosibles: [],
                                identificadoresPropios: [], ayudantesPrivilegiados: [], etiquetasDeServicio: [],
                                grupos: [], equipo: nil, motivoDeProteccion: "Es parte de macOS.")
    return Guardia.rechazo(elemento(casa("Library/Preferences/x.plist")), app: protegida, entorno: entorno) == "Es parte de macOS."
}

// MARK: - Papelera

print("\n▸ Papelera")

final class Registro: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _movidos: [String] = []
    private var _llamadas: [String] = []
    var movidos: [String] { cerrojo.withLock { _movidos } }
    var llamadas: [String] { cerrojo.withLock { _llamadas } }
    func mover(_ u: URL) { cerrojo.withLock { _movidos.append(u.path) } }
    func llamar(_ s: String) { cerrojo.withLock { _llamadas.append(s) } }
}

func papelera(_ registro: Registro, falla: Set<String> = [], respuesta: String = "") -> Papelera {
    Papelera(entorno: entorno,
             mover: { url in
                 if falla.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
                 registro.mover(url)
             },
             ejecutar: { programa, argumentos in
                 registro.llamar(programa + " " + argumentos.joined(separator: " "))
                 return (0, respuesta)
             })
}

let prefs = elemento(casa("Library/Preferences/com.acme.Foo.plist"))
let agente = Elemento(url: casa("Library/LaunchAgents/sync.plist"), categoria: .servicios, tipo: "Agente", confianza: .exacta,
                      motivo: "m", requiereAdmin: false, servicio: ServicioLaunchd(etiqueta: "sync", dominio: .usuario))
let laApp = elemento(fooURL, .aplicacion)

await probarEsperando("mueve todo y deja la app para el final") {
    let r = Registro()
    let informe = await papelera(r).triturar([laApp, prefs, agente], de: foo, conAdmin: false)
    return informe.enviados.count == 3 && informe.fallos.isEmpty && r.movidos.last == fooURL.path
}
await probarEsperando("apaga el servicio del usuario ANTES de mover su plist") {
    let r = Registro()
    let informe = await papelera(r).triturar([agente], de: foo, conAdmin: false)
    return r.llamadas.first == "/bin/launchctl bootout gui/\(getuid())/sync" && informe.serviciosApagados == ["sync"]
}
await probarEsperando("lo que la Guardia rechaza no se mueve") {
    let r = Registro()
    let informe = await papelera(r).triturar([prefs, elemento(casa("Documents/Foo"))], de: foo, conAdmin: false)
    return r.movidos == [prefs.url.path] && informe.fallos.count == 1
}
await probarEsperando("si algo falla, el resto sigue y el fallo por permisos se marca reintentable") {
    let r = Registro()
    let otro = elemento(casa("Library/Caches/com.acme.Foo"))
    let informe = await papelera(r, falla: [prefs.url.path]).triturar([prefs, otro], de: foo, conAdmin: false)
    return informe.enviados.map(\.url) == [otro.url] && informe.fallos.count == 1 && informe.fallos[0].necesitaAdmin
}
await probarEsperando("sin permiso de administrador, lo del sistema queda como fallo reintentable y no se pide contraseña") {
    let r = Registro()
    let demonio = Elemento(url: ruta("Library/LaunchDaemons/com.acme.Foo.Helper.plist"), categoria: .servicios, tipo: "Demonio",
                           confianza: .exacta, motivo: "m", requiereAdmin: true,
                           servicio: ServicioLaunchd(etiqueta: "com.acme.Foo.Helper", dominio: .sistema))
    let informe = await papelera(r).triturar([demonio], de: foo, conAdmin: false)
    return informe.fallos.count == 1 && informe.fallos[0].necesitaAdmin && r.llamadas.isEmpty && r.movidos.isEmpty
}
await probarEsperando("con administrador: una sola llamada a osascript para todo lo del sistema") {
    let r = Registro()
    let a = Elemento(url: ruta("Library/LaunchDaemons/com.acme.Foo.Helper.plist"), categoria: .servicios, tipo: "Demonio",
                     confianza: .exacta, motivo: "m", requiereAdmin: true,
                     servicio: ServicioLaunchd(etiqueta: "com.acme.Foo.Helper", dominio: .sistema))
    let b = Elemento(url: ruta("Library/PrivilegedHelperTools/com.acme.Foo.Helper"), categoria: .servicios, tipo: "Ayudante",
                     confianza: .exacta, motivo: "m", requiereAdmin: true)
    let salida = "OK\t\(a.url.path)\rOK\t\(b.url.path)\r"
    let informe = await papelera(r, respuesta: salida).triturar([a, b], de: foo, conAdmin: true)
    return r.llamadas.count == 1 && r.llamadas[0].hasPrefix("/usr/bin/osascript -e do shell script")
        && informe.enviados.count == 2 && informe.fallos.isEmpty && informe.serviciosApagados == ["com.acme.Foo.Helper"]
}
await probarEsperando("si cancela la contraseña, todo queda como fallo y nada se da por enviado") {
    let cancelo = Papelera(entorno: entorno, mover: { _ in }, ejecutar: { _, _ in (1, "execution error: User canceled. (-128)") })
    let a = Elemento(url: ruta("Library/PrivilegedHelperTools/com.acme.Foo.Helper"), categoria: .servicios, tipo: "Ayudante",
                     confianza: .exacta, motivo: "m", requiereAdmin: true)
    let informe = await cancelo.triturar([a], de: foo, conAdmin: true)
    return informe.enviados.isEmpty && informe.fallos.count == 1 && informe.fallos[0].motivo.contains("Cancelaste")
}

print("\n▸ Guion de administrador (se ejecuta de verdad, sin root, sobre archivos de prueba)")

let areaDelGuion = temporal.appendingPathComponent("guion")
let papeleraFalsa = areaDelGuion.appendingPathComponent(".Trash")
carpeta(papeleraFalsa)
let raros = [areaDelGuion.appendingPathComponent("uno con espacios.plist"),
             areaDelGuion.appendingPathComponent("it's \"raro\" & $HOME.plist"),
             areaDelGuion.appendingPathComponent("ñandú ✓.plist")]
raros.forEach { archivo($0) }
archivo(papeleraFalsa.appendingPathComponent("uno con espacios.plist"), "ya estaba")      // choque de nombres

probar("mueve nombres con espacios, comillas, $ y acentos sin pisar lo que ya había") {
    let elementos = raros.map { Elemento(url: $0, categoria: .servicios, tipo: "t", confianza: .exacta, motivo: "m", requiereAdmin: true) }
        + [Elemento(url: areaDelGuion.appendingPathComponent("no-existe.plist"), categoria: .servicios, tipo: "t",
                    confianza: .exacta, motivo: "m", requiereAdmin: true)]
    let guion = Papelera.guionDeAdministrador(elementos, papelera: papeleraFalsa, uid: getuid(), gid: getgid())
    let r = Papelera.ejecutarDeVerdad("/bin/sh", ["-c", guion])
    let leido = Papelera.leerSalida(r.salida)
    let movidos = raros.allSatisfy { !fm.fileExists(atPath: $0.path) && leido[$0.path] == .ok }
    let enPapelera = (try? fm.contentsOfDirectory(atPath: papeleraFalsa.path).sorted()) ?? []
    return r.estado == 0 && movidos && leido[areaDelGuion.appendingPathComponent("no-existe.plist").path] == .ausente
        && enPapelera.contains("uno con espacios.plist") && enPapelera.contains("uno con espacios.plist 2")
        && (try? String(contentsOf: papeleraFalsa.appendingPathComponent("uno con espacios.plist"))) == "ya estaba"
        && enPapelera.count == 4
}
probar("el literal de AppleScript sobrevive comillas, barras y saltos de línea (ida y vuelta con osascript real)") {
    let texto = "uno \"dos\" \\tres\ncuatro 'cinco' $seis"
    let guion = "printf '%s' " + Papelera.comillas(texto)
    let script = Papelera.appleScript(guion, aviso: "x").replacingOccurrences(of: " with administrator privileges", with: "")
    let r = Papelera.ejecutarDeVerdad("/usr/bin/osascript", ["-e", script])
    return r.estado == 0 && r.salida.trimmingCharacters(in: .newlines).replacingOccurrences(of: "\r", with: "\n") == texto
}

// MARK: - Resumen

print("\n\(pasadas) pasadas, \(falladas) falladas")
exit(falladas == 0 ? 0 : 1)
