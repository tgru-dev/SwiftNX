// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftNX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftNX", targets: ["SwiftNX"]),
        .library(name: "SwiftNXKit", targets: ["SwiftNXKit"]),
    ],
    targets: [
        .target(
            name: "SwiftNXKit",
            path: "Sources/SwiftNXKit"
        ),
        .executableTarget(
            name: "SwiftNX",
            dependencies: ["SwiftNXKit"],
            path: "Sources/SwiftNX"
        ),
        .testTarget(
            name: "SwiftNXKitTests",
            dependencies: ["SwiftNXKit"],
            path: "Tests/SwiftNXKitTests"
        ),
    ]
)
