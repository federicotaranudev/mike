// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mike",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Mike", targets: ["Mike"])
    ],
    dependencies: [
        .package(url: "https://github.com/google-ai-edge/LiteRT-LM", exact: "0.18.1")
    ],
    targets: [
        .target(name: "Mike",
                dependencies: [.product(name: "LiteRTLM", package: "LiteRT-LM")],
                path: "Sources/Mike")
    ],
    swiftLanguageModes: [.v5]
)
