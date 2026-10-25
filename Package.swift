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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "SayKuku",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SayKuku",
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
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
