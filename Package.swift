// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TolerantCodable",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "TolerantCodable", targets: ["TolerantCodable"])
    ],
    targets: [
        .target(name: "TolerantCodable"),
        .testTarget(name: "TolerantCodableTests", dependencies: ["TolerantCodable"])
    ],
    swiftLanguageModes: [.v6]
)
