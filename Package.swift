// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MediaDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MediaDock", targets: ["MediaDock"])
    ],
    targets: [
        .executableTarget(
            name: "MediaDock",
            path: "Sources/MediaDock"
        ),
        .testTarget(
            name: "MediaDockTests",
            dependencies: ["MediaDock"],
            path: "Tests/MediaDockTests"
        )
    ]
)
