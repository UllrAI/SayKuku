// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SayKuku",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SayKuku", targets: ["SayKuku"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "SayKuku",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SayKuku",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SayKukuTests",
            dependencies: ["SayKuku"],
            path: "Tests/SayKukuTests",
            // Read from the source tree through #filePath, not bundled.
            exclude: ["Fixtures"]
        )
    ]
)
