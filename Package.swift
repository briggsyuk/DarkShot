// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DarkShot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DarkShot", targets: ["DarkShot"])],
    targets: [
        .executableTarget(name: "DarkShot")
    ],
    swiftLanguageModes: [.v5]
)
