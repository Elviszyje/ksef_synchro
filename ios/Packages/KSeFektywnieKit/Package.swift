// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KSeFektywnieKit",
    defaultLocalization: "pl",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "KSeFClient", targets: ["KSeFClient"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AppServices", targets: ["AppServices"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Czysta logika domenowa portowana z Django. Bez UIKit/SwiftUI, bez I/O.
        .target(name: "Domain"),
        // Klient API KSeF 2.0 (auth tokenem, zapytania, pobieranie XML).
        .target(name: "KSeFClient", dependencies: ["Domain"]),
        // SQLite (GRDB): schemat, migracje, repozytoria.
        .target(name: "Persistence", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),

        // Orkiestracja: synchronizacja KSeF, (później) lustro iCloud.
        .target(name: "AppServices", dependencies: ["Domain", "KSeFClient", "Persistence"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], resources: [.copy("Fixtures")]),
        .testTarget(name: "KSeFClientTests", dependencies: ["KSeFClient"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "AppServicesTests", dependencies: ["AppServices"]),
    ]
)
