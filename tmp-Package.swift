// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mike",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Mike", targets: ["Mike"])
    ],
    targets: [
        .target(name: "Mike", path: "Sources/Mike")
    ],
    swiftLanguageModes: [.v5]
)
