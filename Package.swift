// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResetWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .executable(name: "Host", targets: ["Host"]),
        .executable(name: "WidgetExtension", targets: ["WidgetExtension"])
    ],
    targets: [
        .target(name: "Shared", path: "Shared/Sources/Shared"),
        .executableTarget(name: "Host", dependencies: ["Shared"], path: "Host/Sources/Host"),
        .executableTarget(
            name: "WidgetExtension",
            dependencies: ["Shared"],
            path: "Widget/Sources/WidgetExtension",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .unsafeFlags([
                    "-application-extension",
                    "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"
                ])
            ]
        )
    ]
)
