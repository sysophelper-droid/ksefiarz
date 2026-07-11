// swift-tools-version: 6.0
// Ksefiarz — natywna aplikacja macOS do zarządzania fakturami i integracji z KSeF.
import PackageDescription

let package = Package(
    name: "Ksefiarz",
    platforms: [
        .macOS(.v14) // celujemy w macOS 14+ (Sonoma)
    ],
    products: [
        .executable(name: "Ksefiarz", targets: ["KsefiarzApp"]),
        .library(name: "KsefiarzCore", targets: ["KsefiarzCore"]),
    ],
    targets: [
        // Logika domenowa, modele SwiftData, usługa KSeF oraz widoki SwiftUI.
        .target(
            name: "KsefiarzCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Cienki target wykonywalny — punkt wejścia aplikacji.
        .executableTarget(
            name: "KsefiarzApp",
            dependencies: ["KsefiarzCore"],
            resources: [
                .copy("Resources/AppIcon.png") // ikona aplikacji (Dock)
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Testy jednostkowe (Swift Testing).
        .testTarget(
            name: "KsefiarzCoreTests",
            dependencies: ["KsefiarzCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
