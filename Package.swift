// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SayKuku",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SayKuku", targets: ["SayKuku"])
    ],
    targets: [
        .executableTarget(
            name: "SayKuku",
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
