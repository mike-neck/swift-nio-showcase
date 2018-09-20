// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "swift-nio-showcase",
    products: [
        .executable(
            name: "HttpClient",
            targets: ["HttpClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.7.2"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "HttpClient",
            dependencies: ["NIO", "NIOHTTP1", "NIOOpenSSL", "NIOConcurrencyHelpers"]),
    ]
)
