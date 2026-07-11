// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLoginManager",
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
            name: "CodexLoginManager"
        ),
        .testTarget(
            name: "CodexLoginManagerTests",
            dependencies: ["CodexLoginManager"]
        )
    ]
)
