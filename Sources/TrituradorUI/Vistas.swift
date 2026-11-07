import AppKit
import SwiftUI
import TrituradorKit

// MARK: - Ventana

/// La ventana entera: cabecera morada arriba y, debajo, la pantalla que toque.
public struct VistaPrincipal: View {
    @ObservedObject var modelo: Modelo
    /// ScrollView es AppKit y sale en blanco en los retratos: ahí se pintan las listas sin él.
    var sinScroll = false
    @State private var soltando = false

    public init(modelo: Modelo) { self.modelo = modelo }

    init(modelo: Modelo, sinScroll: Bool) {
        self.modelo = modelo
        self.sinScroll = sinScroll
    }

    public var body: some View {
        VStack(spacing: 0) {
            Cabecera(lema: lema) { accesorio }
            Group {
                switch modelo.fase {
                case .vacio:
                    PantallaVacia(modelo: modelo, soltando: soltando)
                case .analizando(let nombre):
                    PantallaOcupada(titulo: "Buscando lo que dejó «\(nombre)»…",
                                    detalle: "Miro preferencias, cachés, servicios en segundo plano y ayudantes. Sólo leo: todavía no muevo nada.")
                case .resultados(let resultado):
                    PantallaResultados(modelo: modelo, resultado: resultado, sinScroll: sinScroll)
                case .triturando:
                    PantallaOcupada(titulo: "Triturando…",
                                    detalle: "Si macOS te pide la contraseña, es para mover a la Papelera archivos del sistema.")
                case .listo(let informe, let app):
                    PantallaListo(modelo: modelo, informe: informe, app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tema.fondo)
        .ignoresSafeArea(edges: .top)
        .onDrop(of: [.fileURL], isTargeted: $soltando) { proveedores in
            modelo.recibir(proveedores)
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: soltando)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            modelo.actualizarPermisos()      // por si acaba de dárselo en Ajustes
        }
    }

    private var lema: String {
        switch modelo.fase {
        case .vacio: "Desinstala una app y todo lo que deja escondido en tu sistema"
        case .analizando: "Buscando sus restos…"
        case .resultados: "Revisa la lista y tritura"
        case .triturando: "Triturando…"
        case .listo: "Listo"
        }
    }

    @ViewBuilder private var accesorio: some View {
        if case .resultados = modelo.fase {
            Button { modelo.reiniciar() } label: {
                Label("Otra app", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Volver sin triturar nada")
        }
    }
}

// MARK: - Cabecera

struct Cabecera<Accesorio: View>: View {
    let lema: String
    @ViewBuilder var accesorio: Accesorio

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18))
                DibujoTriturador(estilo: .blanco).frame(width: 34, height: 34)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("CleanUninstall")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(lema)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .contentTransition(.opacity)
            }
            Spacer()
            accesorio
        }
        .padding(.horizontal, 26)
        .padding(.top, 38)                  // aire para los semáforos de la ventana
        .padding(.bottom, 18)
        .background(
            ZStack {
                Tema.degradado
                // Dos luces suaves para que el degradado no se vea plano.
                Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 320, y: -70).blur(radius: 2)
                Circle().fill(Color(suave: 1.0, green: 0.85, blue: 0.40).opacity(0.30)).frame(width: 220).offset(x: -380, y: 50).blur(radius: 34)
            }
            .clipped()
        )
    }
}

// MARK: - Inicio

struct PantallaVacia: View {
    @ObservedObject var modelo: Modelo
    let soltando: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let aviso = modelo.aviso {
                Franja(texto: aviso, icono: "exclamationmark.triangle.fill", color: Tema.ambar) { modelo.aviso = nil }
                    .padding(.horizontal, 20).padding(.top, 14)
            }
            if !modelo.accesoTotal { AvisoDeAccesoTotal().padding(.horizontal, 20).padding(.top, 14) }

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Tema.morado.opacity(0.10)).frame(width: 190, height: 190)
                    Circle().fill(Tema.morado.opacity(0.07)).frame(width: 250, height: 250)
                    DibujoTriturador(recibiendo: soltando).frame(width: 150, height: 150)
                }
                .scaleEffect(soltando ? 1.05 : 1)

                VStack(spacing: 6) {
                    Text("Arrastra una app aquí")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Tema.tinta)
                    Text("CleanUninstall busca lo que la app dejó escondido —preferencias, cachés, servicios en "
                         + "segundo plano y ayudantes con permisos— y lo manda a la Papelera. Nada se borra de verdad.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.tintaSuave)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                Button { modelo.elegirConPanel() } label: {
                    Label("Elegir app…", systemImage: "plus")
                }
                .buttonStyle(BotonPrincipal())
                .keyboardShortcut("o", modifiers: .command)
                .padding(.top, 2)
            }
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(soltando ? AnyShapeStyle(Tema.degradado) : AnyShapeStyle(Tema.borde),
                                  style: StrokeStyle(lineWidth: soltando ? 3 : 2, dash: [10, 6]))
                    .background(RoundedRectangle(cornerRadius: 18).fill(Tema.morado.opacity(soltando ? 0.06 : 0)))
                    .padding(20)
            }
        }
    }
}

/// Mientras busca o tritura: el triturador trabajando.
struct PantallaOcupada: View {
    let titulo: String
    let detalle: String

    var body: some View {
        VStack(spacing: 18) {
            DibujoTriturador(triturando: true).frame(width: 130, height: 130)
            Text(titulo)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.tinta)
            Text(detalle)
                .font(.system(size: 13))
                .foregroundStyle(Tema.tintaSuave)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }
}

// MARK: - Resultados

struct PantallaResultados: View {
    @ObservedObject var modelo: Modelo
    let resultado: Resultado
    var sinScroll = false

    private var grupos: [(categoria: Categoria, elementos: [Elemento])] {
        Categoria.allCases.compactMap { categoria in
            let elementos = resultado.elementos.filter { $0.categoria == categoria }
            return elementos.isEmpty ? nil : (categoria, elementos)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TarjetaDeApp(modelo: modelo, resultado: resultado)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)

            if resultado.estaAbierta {
                Franja(texto: "«\(resultado.app.nombre)» está abierta. Se cerrará antes de triturar.",
                       icono: "power.circle.fill", color: Tema.ambar, cerrar: nil)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
            if !resultado.carpetasSinAcceso.isEmpty || !modelo.accesoTotal {
                AvisoDeAccesoTotal().padding(.horizontal, 20).padding(.top, 8)
            }

            Group {
                if sinScroll { lista } else { ScrollView { lista } }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            BarraDeTrituracion(modelo: modelo)
        }
    }

    private var lista: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(grupos, id: \.categoria) { grupo in
                VStack(alignment: .leading, spacing: 8) {
                    TituloDeGrupo(modelo: modelo, categoria: grupo.categoria, elementos: grupo.elementos)
                    VStack(spacing: 0) {
                        ForEach(Array(grupo.elementos.enumerated()), id: \.element.id) { indice, elemento in
                            FilaDeElemento(elemento: elemento, marcado: modelo.seleccion.contains(elemento.url),
                                           alternar: { modelo.alternar(elemento) },
                                           mostrar: { NSWorkspace.shared.activateFileViewerSelecting([elemento.url]) })
                            if indice < grupo.elementos.count - 1 {
                                Rectangle().fill(Tema.borde.opacity(0.7)).frame(height: 1).padding(.leading, 62)
                            }
                        }
                    }
                    .tarjeta()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Arriba de la lista: qué app es, cuánto ocupa todo lo suyo y el selector de qué marcar.
struct TarjetaDeApp: View {
    @ObservedObject var modelo: Modelo
    let resultado: Resultado

    var body: some View {
        HStack(spacing: 14) {
            IconoDeApp(url: resultado.app.url).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(resultado.app.nombre)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text([resultado.app.version.map { "Versión \($0)" }, resultado.app.identificador].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.tintaSuave)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(resultado.elementos.count) elementos · \(Formato.bytes(resultado.tamañoTotal)) en total")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Tema.acento)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text("MARCAR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Tema.tintaSuave)
                Segmentos(opciones: [(.seguros, "Seguros"), (.probables, "Con probables"), (.todo, "Todo")],
                          seleccion: Binding(get: { modelo.modo }, set: { modelo.modo = $0 }))
            }
        }
        .padding(14)
        .tarjeta()
    }
}

/// El icono de la app, rasterizado una vez: pintar el `NSImage` de NSWorkspace directamente
/// funciona en la ventana, pero ImageRenderer (los retratos) lo estropea.
struct IconoDeApp: View {
    let url: URL

    var body: some View {
        let icono = NSWorkspace.shared.icon(forFile: url.path)
        icono.size = NSSize(width: 104, height: 104)
        if let imagen = icono.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return AnyView(Image(decorative: imagen, scale: 2).resizable().interpolation(.high))
        }
        return AnyView(Image(systemName: "app.fill").resizable().foregroundStyle(Tema.tintaSuave))
    }
}

struct TituloDeGrupo: View {
    @ObservedObject var modelo: Modelo
    let categoria: Categoria
    let elementos: [Elemento]

    var body: some View {
        let marcados = elementos.filter { modelo.seleccion.contains($0.url) }.count
        HStack(spacing: 8) {
            Image(systemName: categoria.icono)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tema.acento)
            Text(categoria.titulo.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Tema.tintaSuave)
            Text("\(marcados)/\(elementos.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.acento)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Tema.morado.opacity(0.10)))
            Spacer()
            Text(Formato.bytes(elementos.reduce(0) { $0 + $1.tamaño }))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tema.tintaSuave)
            Button(marcados == elementos.count ? "Quitar todos" : "Marcar todos") { modelo.alternar(grupo: elementos) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Tema.acento)
        }
        .padding(.horizontal, 4)
    }
}

struct FilaDeElemento: View {
    let elemento: Elemento
    let marcado: Bool
    let alternar: () -> Void
    let mostrar: () -> Void
    @State private var encima = false

    var body: some View {
        HStack(spacing: 12) {
            Casilla(marcada: marcado)
            IconoDeCategoria(categoria: elemento.categoria)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(elemento.nombre)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Tema.tinta)
                        .lineLimit(1).truncationMode(.middle)
                    Etiqueta(texto: elemento.tipo, color: Tema.tintaSuave, relleno: false)
                    if elemento.confianza != .exacta {
                        Etiqueta(texto: elemento.confianza.etiqueta, color: elemento.confianza == .dudosa ? Tema.rojo : Tema.ambar)
                    }
                    if elemento.servicio != nil { Etiqueta(texto: "Se apaga antes", color: Tema.indigo, icono: "power") }
                    if elemento.requiereAdmin { Etiqueta(texto: "Pide contraseña", color: Tema.tintaSuave, icono: "lock.fill") }
                }
                Text(Formato.ruta(elemento.url.deletingLastPathComponent()))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.tintaSuave)
                    .lineLimit(1).truncationMode(.middle)
                Text(elemento.motivo + (elemento.nota.map { " · \($0)" } ?? ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(elemento.nota != nil ? Tema.rojo : Tema.tintaSuave.opacity(0.85))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(Formato.bytes(elemento.tamaño))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Tema.tinta)
                .monospacedDigit()
            Button(action: mostrar) { Image(systemName: "magnifyingglass") }
                .buttonStyle(BotonIcono())
                .help("Mostrar en Finder")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(encima ? Tema.morado.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: alternar)
        .onHover { encima = $0 }
        .opacity(marcado ? 1 : 0.72)
        .animation(.easeOut(duration: 0.12), value: marcado)
    }
}

struct BarraDeTrituracion: View {
    @ObservedObject var modelo: Modelo

    var body: some View {
        let elegidos = modelo.seleccionados.count
        let total = modelo.resultado?.elementos.count ?? 0
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(elegidos) de \(total) elementos")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                Text("\(Formato.bytes(modelo.bytesSeleccionados)) · irán a la Papelera, no se borran")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.tintaSuave)
            }
            Spacer()
            Button("Cancelar") { modelo.reiniciar() }
                .buttonStyle(BotonSecundario())
            Button { Task { await modelo.triturar() } } label: {
                Label("Triturar\(elegidos > 0 ? " \(elegidos)" : "")", systemImage: "scissors")
            }
            .buttonStyle(BotonPrincipal())
            .disabled(elegidos == 0)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .modifier(FondoDeBarra())
    }
}

// MARK: - Final

struct PantallaListo: View {
    @ObservedObject var modelo: Modelo
    let informe: Informe
    let app: AppObjetivo

    private var hayReintentables: Bool { informe.fallos.contains(where: \.necesitaAdmin) }
    private var laAppSeFue: Bool { informe.enviados.contains { $0.categoria == .aplicacion } }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill((informe.fallos.isEmpty ? Tema.verde : Tema.ambar).opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: informe.fallos.isEmpty ? "checkmark" : "exclamationmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(informe.fallos.isEmpty ? Tema.verde : Tema.ambar)
            }
            VStack(spacing: 6) {
                Text(titulo)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Tema.tinta)
                    .multilineTextAlignment(.center)
                Text(subtitulo)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.tintaSuave)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            if !informe.fallos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(informe.fallos.enumerated()), id: \.offset) { indice, fallo in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fallo.elemento.nombre)
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Tema.tinta)
                                .lineLimit(1).truncationMode(.middle)
                            Text(fallo.motivo).font(.system(size: 11.5)).foregroundStyle(Tema.rojo)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if indice < informe.fallos.count - 1 { Rectangle().fill(Tema.borde).frame(height: 1) }
                    }
                }
                .tarjeta()
                .frame(maxWidth: 520)
            }

            HStack(spacing: 10) {
                if hayReintentables {
                    Button { Task { await modelo.reintentarConAdmin() } } label: {
                        Label("Reintentar con contraseña", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(BotonPrincipal(relleno: Tema.degradadoAviso, sombra: Tema.ambar))
                } else if !informe.enviados.isEmpty {
                    Button { abrirPapelera() } label: { Label("Abrir la Papelera", systemImage: "trash") }
                        .buttonStyle(BotonPrincipal())
                }
                Button("Triturar otra app") { modelo.reiniciar() }
                    .buttonStyle(BotonSecundario())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(36)
    }

    private var titulo: String {
        if informe.enviados.isEmpty { return "No se pudo triturar nada" }
        if informe.fallos.isEmpty && laAppSeFue { return "«\(app.nombre)» ya está en la Papelera" }
        if informe.fallos.isEmpty { return "Listo: \(informe.enviados.count) elementos en la Papelera" }
        return "Se trituró casi todo"
    }

    private var subtitulo: String {
        var partes: [String] = []
        if !informe.enviados.isEmpty {
            partes.append("\(informe.enviados.count) elemento\(informe.enviados.count == 1 ? "" : "s") "
                          + "(\(Formato.bytes(informe.bytesLiberados))) en la Papelera. El espacio se libera cuando la vacíes.")
        }
        if !informe.serviciosApagados.isEmpty {
            partes.append("Se apagaron \(informe.serviciosApagados.count) servicio\(informe.serviciosApagados.count == 1 ? "" : "s") en segundo plano.")
        }
        if !informe.fallos.isEmpty {
            partes.append("\(informe.fallos.count) no se pudo\(informe.fallos.count == 1 ? "" : "ieron") mover:")
        }
        return partes.joined(separator: " ")
    }

    private func abrirPapelera() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}

// MARK: - Piezas

/// Aviso con color a la izquierda. `cerrar == nil` no lleva botón de cerrar.
struct Franja: View {
    let texto: String
    let icono: String
    let color: Color
    let cerrar: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icono).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(texto).font(.system(size: 12.5)).foregroundStyle(Tema.tinta)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let cerrar {
                Button(action: cerrar) { Image(systemName: "xmark") }.buttonStyle(BotonIcono())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

struct AvisoDeAccesoTotal: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.ambar)
            Text("CleanUninstall no tiene «Acceso total al disco». Sin él macOS le esconde parte de los datos de otras apps, "
                 + "y la lista puede quedar incompleta.")
                .font(.system(size: 12.5)).foregroundStyle(Tema.tinta)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Abrir Ajustes") { Permisos.abrirAjustesDeAccesoTotal() }
                .buttonStyle(BotonSecundario(compacto: true))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tema.ambar.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tema.ambar.opacity(0.35), lineWidth: 1))
    }
}

/// La casilla de cada fila: redonda, con el degradado de llama cuando está marcada.
struct Casilla: View {
    let marcada: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(marcada ? AnyShapeStyle(Tema.degradadoBoton) : AnyShapeStyle(Color.clear))
                .overlay(Circle().strokeBorder(marcada ? Color.clear : Tema.tintaSuave.opacity(0.45), lineWidth: 1.5))
            if marcada {
                Image(systemName: "checkmark").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .shadow(color: marcada ? Tema.morado.opacity(0.30) : .clear, radius: 4, y: 2)
        .accessibilityLabel(marcada ? "Marcado" : "Sin marcar")
    }
}

struct IconoDeCategoria: View {
    let categoria: Categoria

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(categoria.degradado)
            Image(systemName: categoria.icono).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
        .shadow(color: Tema.morado.opacity(0.22), radius: 4, y: 2)
    }
}

struct Etiqueta: View {
    let texto: String
    let color: Color
    var relleno = true
    var icono: String?

    var body: some View {
        HStack(spacing: 3) {
            if let icono { Image(systemName: icono).font(.system(size: 8, weight: .bold)) }
            Text(texto).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(relleno ? 0.14 : 0)))
        .overlay(Capsule().strokeBorder(color.opacity(relleno ? 0 : 0.35), lineWidth: 1))
        .fixedSize()
    }
}

/// Control segmentado propio: el del sistema sale gris y no combina con el morado.
struct Segmentos<Valor: Hashable>: View {
    let opciones: [(valor: Valor, texto: String)]
    @Binding var seleccion: Valor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opciones, id: \.valor) { opcion in
                let elegida = opcion.valor == seleccion
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { seleccion = opcion.valor }
                } label: {
                    Text(opcion.texto)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(elegida ? .white : Tema.tintaSuave)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(elegida ? AnyShapeStyle(Tema.degradadoBoton) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Tema.tarjeta))
        .overlay(Capsule().strokeBorder(Tema.borde, lineWidth: 1))
        .fixedSize()
    }
}

/// Fondo de tarjeta blanca (berenjena de noche) con borde suave que se tiñe al pasar el ratón.
struct FondoDeTarjeta: ViewModifier {
    var radio: CGFloat = 16
    @State private var encima = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radio).fill(Tema.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: radio)
                .strokeBorder(encima ? Tema.morado.opacity(0.35) : Tema.borde, lineWidth: 1))
            .shadow(color: Tema.morado.opacity(encima ? 0.12 : 0.05), radius: encima ? 10 : 5, y: 3)
            .onHover { encima = $0 }
            .animation(.easeOut(duration: 0.15), value: encima)
    }
}

extension View {
    func tarjeta(radio: CGFloat = 16) -> some View { modifier(FondoDeTarjeta(radio: radio)) }
}

/// La barra de abajo: blanca, con una línea fina encima.
struct FondoDeBarra: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Tema.tarjeta)
            .overlay(alignment: .top) { Rectangle().fill(Tema.borde).frame(height: 1) }
    }
}

extension Categoria {
    /// El color de cada grupo, para reconocerlos de un vistazo.
    var degradado: LinearGradient {
        switch self {
        case .aplicacion: Tema.degradadoBoton
        case .servicios: Tema.degradadoMorado
        case .datos: Tema.degradadoCalido
        case .cache: Tema.degradadoAviso
        case .complementos: LinearGradient(colors: [Tema.verde, Color(suave: 0.08, green: 0.50, blue: 0.40)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .recibos: LinearGradient(colors: [Color(suave: 0.55, green: 0.50, blue: 0.68), Color(suave: 0.38, green: 0.33, blue: 0.52)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
