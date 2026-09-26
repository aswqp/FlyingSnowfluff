// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlyingSnowfluff",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "FlyingSnowfluffCore", targets: ["FlyingSnowfluffCore"]),
        .executable(name: "FlyingSnowfluffApp", targets: ["FlyingSnowfluffApp"]),
        .executable(name: "flyingsnowfluffctl", targets: ["flyingsnowfluffctl"])
    ],
    targets: [
        .target(name: "FlyingSnowfluffCore"),
        .executableTarget(
            name: "FlyingSnowfluffApp",
            dependencies: ["FlyingSnowfluffCore"]
        ),
        .executableTarget(
            name: "flyingsnowfluffctl",
            dependencies: ["FlyingSnowfluffCore"]
        ),
        .testTarget(
            name: "FlyingSnowfluffCoreTests",
            dependencies: ["FlyingSnowfluffCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
