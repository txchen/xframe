// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "XFrame",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "XFrame", targets: ["XFrame"])],
    dependencies: [.package(url: "https://github.com/stasel/WebRTC.git", exact: "153.0.0")],
    targets: [
        .executableTarget(name: "XFrame", dependencies: [.product(name: "WebRTC", package: "WebRTC")],
                          resources: [.copy("Shaders.metal")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "XFrameTests", dependencies: ["XFrame"])
    ]
)
