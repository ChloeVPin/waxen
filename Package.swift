// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "waxen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "waxen", targets: ["waxen"]),
        .library(name: "WaxenCore", targets: ["WaxenCore"])
    ],
    targets: [
        .target(
            name: "WaxenCore"
        ),
        .executableTarget(
            name: "waxen",
            dependencies: ["WaxenCore"]
        ),
        .testTarget(
            name: "WaxenCoreTests",
            dependencies: ["WaxenCore"]
        )
    ]
)
