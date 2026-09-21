// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "XFrame",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "XFrame", targets: ["XFrame"])],
    targets: [
        .executableTarget(name: "XFrame", resources: [.copy("Shaders.metal")]),
        .testTarget(name: "XFrameTests", dependencies: ["XFrame"])
    ]
)
