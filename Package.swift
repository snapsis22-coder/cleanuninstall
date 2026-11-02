// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Triturador",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrituradorKit", targets: ["TrituradorKit"]),
        .library(name: "TrituradorUI", targets: ["TrituradorUI"]),
        .executable(name: "Triturador", targets: ["Triturador"]),
        .executable(name: "trituradortests", targets: ["trituradortests"]),
        .executable(name: "trituradorshot", targets: ["trituradorshot"]),
    ],
    targets: [
        // Motor: lee la app, busca sus restos, decide qué tan seguro es cada uno y
        // los manda a la Papelera. Sin nada de interfaz, para probarlo sin ventana.
        .target(name: "TrituradorKit"),

        // Las vistas viven en una librería y no en el ejecutable porque las
        // previews de SwiftUI no funcionan dentro de un executableTarget.
        .target(name: "TrituradorUI", dependencies: ["TrituradorKit"]),

        .executableTarget(name: "Triturador", dependencies: ["TrituradorUI"]),
        .executableTarget(name: "trituradortests", dependencies: ["TrituradorKit", "TrituradorUI"]),
        // Retratos de la interfaz a PNG, para revisarla sin permiso de captura.
        .executableTarget(name: "trituradorshot", dependencies: ["TrituradorKit", "TrituradorUI"]),
    ]
)
