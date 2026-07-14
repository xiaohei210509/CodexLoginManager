// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLoginManager",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexLoginManager",
            targets: ["CodexLoginManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexLoginManager",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexLoginManagerTests",
            dependencies: ["CodexLoginManager"]
        )
    ]
)
