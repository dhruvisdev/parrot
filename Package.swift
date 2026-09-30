// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Parrot",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Parrot", targets: ["Parrot"])],
    targets: [.executableTarget(name: "Parrot"), .testTarget(name: "ParrotTests", dependencies: ["Parrot"])],
    swiftLanguageModes: [.v5]
)
