// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TransormaCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "TransormaCore", targets: ["TransormaCore"]),
        .executable(name: "transorma-diagnostics", targets: ["TransormaDiagnostics"])
    ],
    targets: [
        .systemLibrary(name: "CMailSystem", path: "Sources/CMailSystem"),
        .target(name: "TransormaCore", dependencies: ["CMailSystem"],
                swiftSettings: [.unsafeFlags(["-application-extension", "-Xcc", "-iwithsysroot", "-Xcc", "/usr/include/libxml2"])]),
        .executableTarget(name: "TransormaDiagnostics", dependencies: ["TransormaCore"], path: "Tools/Diagnostics"),
        .testTarget(name: "TransormaCoreTests", dependencies: ["TransormaCore"])
    ]
)
