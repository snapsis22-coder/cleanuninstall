import SwiftUI

/// El triturador de papel: una hoja que entra por la ranura del cabezal y, debajo, el cajón por
/// donde caen las tiras. Está dibujado con `Canvas` para que sirva igual de grande (la zona de
/// arrastre) que de pequeño (la cabecera), y para poder animar sólo las tiras.
struct DibujoTriturador: View {
    enum Estilo {
        /// Cuerpo con el degradado de llama, para el fondo claro de la app.
        case color
        /// Blanco translúcido, para ir sobre el degradado de la cabecera.
        case blanco
    }

    var estilo: Estilo = .color
    /// Hay algo encima, a punto de soltarse: la hoja baja un poco hacia la ranura.
    var recibiendo = false
    /// Está triturando: las tiras caen sin parar.
    var triturando = false
    /// Para los retratos: congela la animación en un instante conocido.
    var instanteFijo: Double?

    var body: some View {
        if triturando && instanteFijo == nil {
            TimelineView(.animation) { contexto in
                lienzo(contexto.date.timeIntervalSinceReferenceDate)
            }
        } else {
            lienzo(instanteFijo ?? 0)
        }
    }

    private func lienzo(_ t: Double) -> some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 100          // 1 unidad = 1 % del lado
            let ox = (size.width - 100 * u) / 2, oy = (size.height - 100 * u) / 2
            func caja(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
                Path(roundedRect: CGRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u), cornerRadius: r * u)
            }
            let color = estilo == .color

            // Paleta según el estilo.
            let cabezal: GraphicsContext.Shading = color
                ? .linearGradient(Gradient(colors: [Tema.naranja, Tema.rosa]),
                                  startPoint: CGPoint(x: ox, y: oy + 14 * u), endPoint: CGPoint(x: ox + 100 * u, y: oy + 44 * u))
                : .color(.white)
            let cuerpo: GraphicsContext.Shading = color
                ? .linearGradient(Gradient(colors: [Tema.rosa, Tema.morado]),
                                  startPoint: CGPoint(x: ox, y: oy + 44 * u), endPoint: CGPoint(x: ox + 100 * u, y: oy + 90 * u))
                : .color(.white.opacity(0.78))
            let hueco: Color = color ? Tema.indigo.opacity(0.92) : Color.black.opacity(0.28)
            let tira = Color.white.opacity(0.95)

            // Sombra suave en el suelo.
            if color {
                ctx.fill(Path(ellipseIn: CGRect(x: ox + 16 * u, y: oy + 90 * u, width: 68 * u, height: 7 * u)),
                         with: .color(Tema.morado.opacity(0.16)))
            }

            // La hoja: se dibuja primero para que el cabezal la tape por abajo, como si entrara.
            let bajada = recibiendo ? 9.0 : 0.0
            let hoja = caja(30, 2 + bajada, 40, 34, 3)
            ctx.fill(hoja, with: .color(.white))
            if color { ctx.stroke(hoja, with: .color(Tema.borde), lineWidth: max(1, 0.9 * u)) }
            for i in 0..<3 {                                    // renglones
                ctx.fill(caja(36, 9 + bajada + Double(i) * 6, i == 2 ? 16 : 28, 2.2, 1.1),
                         with: .color(color ? Tema.tintaSuave.opacity(0.35) : Color.gray.opacity(0.5)))
            }

            // Cuerpo y cajón.
            ctx.fill(caja(21, 42, 58, 46, 7), with: cuerpo)
            ctx.fill(caja(28, 56, 44, 26, 4), with: .color(hueco))

            // Tiras que caen dentro del cajón (recortadas a la ventana).
            var dentro = ctx
            dentro.clip(to: caja(28, 56, 44, 26, 4))
            let tiras = 9
            for i in 0..<tiras {
                let x = 31.2 + Double(i) * 4.6
                let largo = 10.0 + Double((i * 7) % 5) * 2.6
                // Quietas: cuelgan a distintas alturas. Triturando: bajan y se repiten.
                let base = Double((i * 5) % 7) * 3.4
                let desplazamiento = triturando ? (t * 26 + Double(i) * 7).truncatingRemainder(dividingBy: 34) : 0
                dentro.fill(caja(x, 52 + base + desplazamiento, 2.8, largo, 1.2),
                            with: .color(tira.opacity(0.55 + 0.45 * Double((i * 3) % 4) / 3)))
                if triturando {                                  // segunda vuelta para que no haya huecos
                    dentro.fill(caja(x, 52 + base + desplazamiento - 34, 2.8, largo, 1.2),
                                with: .color(tira.opacity(0.55 + 0.45 * Double((i * 3) % 4) / 3)))
                }
            }

            // El cabezal, con su ranura.
            ctx.fill(caja(12, 24, 76, 24, 8), with: cabezal)
            ctx.fill(caja(22, 31, 56, 6.5, 3.2), with: .color(color ? Tema.indigo : Color.black.opacity(0.35)))
            // Un destello arriba para que no se vea plano.
            ctx.fill(caja(16, 26.5, 68, 2.4, 1.2), with: .color(.white.opacity(color ? 0.30 : 0.45)))

            // Botoncito.
            ctx.fill(Path(ellipseIn: CGRect(x: ox + 72.5 * u, y: oy + 46.5 * u, width: 3.6 * u, height: 3.6 * u)),
                     with: .color(.white.opacity(0.85)))
        }
        .accessibilityHidden(true)
    }
}
