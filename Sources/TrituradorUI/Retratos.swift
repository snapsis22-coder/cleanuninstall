import SwiftUI
import TrituradorKit

/// Puerta pública para que la herramienta de retratos pueda pintar cada pantalla por separado,
/// sin volver públicas las vistas ni abrir una ventana de verdad. Los datos son de muestra.
public enum Retratos {

    /// Una app real de este Mac para que la tarjeta lleve su icono; si no hay ninguna, SubFix.
    @MainActor
    private static func appDeMuestra() -> AppObjetivo? {
        for ruta in ["/Applications/Google Chrome.app", "/Applications/TeamViewer.app", "/Applications/SubFix.app"] {
            if let app = try? AppObjetivo.leer(URL(fileURLWithPath: ruta)) { return app }
        }
        return nil
    }

    private static func e(_ ruta: String, _ categoria: Categoria, _ tipo: String, _ confianza: Confianza, _ motivo: String,
                          _ mb: Double, admin: Bool = false, servicio: String? = nil, dominio: ServicioLaunchd.Dominio = .sistema,
                          nota: String? = nil) -> Elemento {
        Elemento(url: URL(fileURLWithPath: ruta), categoria: categoria, tipo: tipo, confianza: confianza, motivo: motivo,
                 requiereAdmin: admin, tamaño: Int64(mb * 1_000_000),
                 servicio: servicio.map { ServicioLaunchd(etiqueta: $0, dominio: dominio) }, nota: nota)
    }

    @MainActor
    private static func muestra() -> Resultado? {
        guard let app = appDeMuestra() else { return nil }
        let casa = NSHomeDirectory()
        let elementos: [Elemento] = [
            e(app.url.path, .aplicacion, "Aplicación", .exacta, "La app que elegiste", 564),
            e("/Library/PrivilegedHelperTools/com.acme.Helper", .servicios, "Ayudante privilegiado", .exacta,
              "Lo ejecuta el servicio «com.acme.Helper»", 2.5, admin: true),
            e("/Library/LaunchDaemons/com.acme.Helper.plist", .servicios, "Demonio", .exacta, "Está asociado a la app o a uno de sus servicios",
              0.004, admin: true, servicio: "com.acme.Helper"),
            e("/Library/LaunchDaemons/com.acme.Watcher.plist", .servicios, "Demonio", .exacta, "Ejecuta algo que está dentro de la app",
              0.004, admin: true, servicio: "com.acme.Watcher"),
            e("\(casa)/Library/Preferences/com.acme.App.plist", .datos, "Preferencias", .exacta, "Lleva el identificador de la app", 0.02),
            e("\(casa)/Library/Containers/com.acme.App", .datos, "Contenedor", .exacta, "Mismo identificador que la app", 102),
            e("\(casa)/Library/Application Support/Acme/App", .datos, "Datos", .porNombre,
              "Se llama igual que la app (dentro de la carpeta «Acme»)", 4596),
            e("\(casa)/Library/Group Containers/ABCDE12345.com.acme.oneauth", .datos, "Datos compartidos", .dudosa,
              "Carpeta compartida con otras apps", 0.2, nota: "También la usa: Windows App"),
            e("\(casa)/Library/Caches/com.acme.App", .cache, "Caché", .exacta, "Mismo identificador que la app", 18.9),
            e("\(casa)/Library/HTTPStorages/com.acme.App", .cache, "Datos de red", .exacta, "Mismo identificador que la app", 2.2),
            e("\(casa)/Library/Caches/Acme/App", .cache, "Caché", .porNombre, "Se llama igual que la app (dentro de la carpeta «Acme»)", 3307),
            e("/var/db/receipts/com.acme.app.bom", .recibos, "Recibo", .exacta, "Lleva el identificador de la app", 1.7, admin: true),
        ]
        return Resultado(app: app, elementos: elementos, estaAbierta: false)
    }

    @MainActor
    public static func inicio(soltando: Bool = false, sinAcceso: Bool = false, aviso: String? = nil) -> some View {
        Pantalla(modelo: Modelo(fase: .vacio, aviso: aviso, accesoTotal: !sinAcceso), soltando: soltando)
    }

    @MainActor
    public static func resultados(abierta: Bool = false, sinAcceso: Bool = false) -> some View {
        guard let r = muestra() else { return AnyView(Text("No hay ninguna app de muestra en este Mac")) }
        let resultado = Resultado(app: r.app, elementos: r.elementos, estaAbierta: abierta)
        let marcados = Set(r.elementos.filter(\.marcadoDeEntrada).map(\.url))
        return AnyView(Pantalla(modelo: Modelo(fase: .resultados(resultado), seleccion: marcados, accesoTotal: !sinAcceso), sinScroll: true))
    }

    @MainActor
    public static func triturando() -> some View {
        Pantalla(modelo: Modelo(fase: .triturando))
    }

    @MainActor
    public static func listo(conFallos: Bool = false) -> some View {
        guard let r = muestra() else { return AnyView(Text("No hay ninguna app de muestra en este Mac")) }
        let enviados = conFallos ? Array(r.elementos.dropLast(3)) : r.elementos
        let fallos = conFallos
            ? r.elementos.suffix(2).map {
                Informe.Fallo(elemento: $0, motivo: "Cancelaste la petición de contraseña.", necesitaAdmin: true)
            } : []
        let informe = Informe(enviados: enviados, fallos: fallos, serviciosApagados: ["com.acme.Helper", "com.acme.Watcher"])
        return AnyView(Pantalla(modelo: Modelo(fase: .listo(informe, r.app))))
    }

    /// El triturador solo, a varios tamaños y en las tres posturas.
    @MainActor
    public static func dibujo() -> some View {
        HStack(spacing: 28) {
            DibujoTriturador().frame(width: 160, height: 160)
            DibujoTriturador(recibiendo: true).frame(width: 160, height: 160)
            DibujoTriturador(triturando: true, instanteFijo: 0.6).frame(width: 160, height: 160)
            ZStack {
                LinearGradient(colors: [Tema.naranja, Tema.rosa, Tema.morado, Tema.lila], startPoint: .topLeading, endPoint: .bottomTrailing)
                DibujoTriturador(estilo: .blanco).padding(14)
            }
            .frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .padding(28).background(Tema.fondo)
    }

    private struct Pantalla: View {
        @StateObject var modelo: Modelo
        var soltando = false
        var sinScroll = false
        init(modelo: Modelo, soltando: Bool = false, sinScroll: Bool = false) {
            _modelo = StateObject(wrappedValue: modelo)
            self.soltando = soltando
            self.sinScroll = sinScroll
        }
        var body: some View {
            VistaPrincipal(modelo: modelo, sinScroll: sinScroll)
        }
    }
}
