#!/usr/bin/env swift
// Dibuja el icono de Triturador por código y arma el .icns.
//
//     swift herramientas/hacer_icono.swift
//
// Igual que en SubFix: nada de recursos externos, todo CoreGraphics. El triturador es el mismo
// dibujo de la interfaz (DibujoTriturador), en blanco sobre el degradado de llama.

import AppKit

let lado = 1024.0
let espacio = CGColorSpaceCreateDeviceRGB()

/// Misma regla que la interfaz (`intensidadDeLaPaleta` en Tema.swift): 20 % menos saturación.
let intensidad = 0.64
func color(_ r: Double, _ v: Double, _ a: Double, _ alfa: Double = 1) -> CGColor {
    let origen = NSColor(red: r, green: v, blue: a, alpha: 1).usingColorSpace(.deviceRGB)!
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
    origen.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
    let suave = NSColor(hue: h, saturation: s * intensidad, brightness: b, alpha: alfa).usingColorSpace(.deviceRGB)!
    return CGColor(red: suave.redComponent, green: suave.greenComponent, blue: suave.blueComponent, alpha: alfa)
}

func dibujar(_ ctx: CGContext) {
    // Fondo: el rectángulo redondeado de macOS con el degradado de llama.
    let fondo = CGRect(x: 0, y: 0, width: lado, height: lado).insetBy(dx: lado * 0.08, dy: lado * 0.08)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: fondo, cornerWidth: lado * 0.2237, cornerHeight: lado * 0.2237, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: espacio,
                                      colors: [color(1.0, 0.58, 0.04), color(1.0, 0.22, 0.31), color(0.89, 0.08, 0.53), color(0.50, 0.25, 0.95)] as CFArray,
                                      locations: [0, 0.38, 0.68, 1])!,
                           start: CGPoint(x: lado * 0.1, y: lado * 0.95), end: CGPoint(x: lado * 0.9, y: lado * 0.05), options: [])
    ctx.restoreGState()

    // El triturador, en una caja de 100×100 unidades centrada y de ~62 % del icono.
    let u = lado * 0.62 / 100
    let ox = (lado - 100 * u) / 2, oy = (lado - 100 * u) / 2 - lado * 0.015
    func caja(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> CGPath {
        CGPath(roundedRect: CGRect(x: ox + x * u, y: oy + (100 - y - h) * u, width: w * u, height: h * u),
               cornerWidth: r * u, cornerHeight: r * u, transform: nil)
    }
    func rellenar(_ p: CGPath, _ c: CGColor) { ctx.setFillColor(c); ctx.addPath(p); ctx.fillPath() }

    // Sombra bajo el aparato.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -lado * 0.012), blur: lado * 0.035, color: color(0.25, 0, 0.25, 0.35))
    rellenar(caja(21, 42, 58, 46, 7), color(1, 1, 1, 0.80))
    rellenar(caja(12, 24, 76, 24, 8), color(1, 1, 1))
    ctx.restoreGState()

    // Hoja (antes del cabezal: éste la tapa por abajo, como si entrara).
    rellenar(caja(30, 1, 40, 34, 3), color(1, 1, 1))
    for i in 0..<3 {
        rellenar(caja(36, 8 + Double(i) * 6, i == 2 ? 16 : 28, 2.4, 1.2), color(0.62, 0.48, 0.72, 0.55))
    }
    // Cuerpo, ventana y tiras.
    rellenar(caja(21, 42, 58, 46, 7), color(1, 1, 1, 0.82))
    rellenar(caja(28, 56, 44, 26, 4), color(0.45, 0.12, 0.62, 0.92))
    ctx.saveGState()
    ctx.addPath(caja(28, 56, 44, 26, 4)); ctx.clip()
    for i in 0..<9 {
        let x = 31.2 + Double(i) * 4.6
        let largo = 10.0 + Double((i * 7) % 5) * 2.6
        let base = Double((i * 5) % 7) * 3.4
        rellenar(caja(x, 52 + base, 2.8, largo, 1.2), color(1, 1, 1, 0.55 + 0.45 * Double((i * 3) % 4) / 3))
    }
    ctx.restoreGState()
    // Cabezal con su ranura.
    rellenar(caja(12, 24, 76, 24, 8), color(1, 1, 1))
    rellenar(caja(22, 31, 56, 6.5, 3.2), color(0.50, 0.18, 0.70, 0.85))
}

let carpeta = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = carpeta.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let ctx = CGContext(data: nil, width: Int(lado), height: Int(lado), bitsPerComponent: 8, bytesPerRow: 0,
                          space: espacio, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("sin lienzo") }
dibujar(ctx)
guard let maestra = ctx.makeImage() else { fatalError("no se pudo pintar") }

let medidas: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (medida, nombre) in medidas {
    guard let chico = CGContext(data: nil, width: medida, height: medida, bitsPerComponent: 8, bytesPerRow: 0,
                                space: espacio, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    chico.interpolationQuality = .high
    chico.draw(maestra, in: CGRect(x: 0, y: 0, width: medida, height: medida))
    guard let imagen = chico.makeImage() else { continue }
    let mapa = NSBitmapImageRep(cgImage: imagen)
    mapa.size = NSSize(width: medida, height: medida)
    guard let png = mapa.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appendingPathComponent("\(nombre).png"))
}
// Una copia grande para mirarla.
if let png = NSBitmapImageRep(cgImage: maestra).representation(using: .png, properties: [:]) {
    try png.write(to: carpeta.appendingPathComponent("Resources/icono-vista-previa.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", carpeta.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil falló")
