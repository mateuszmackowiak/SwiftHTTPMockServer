// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HTTPMockServer",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [ .library(name: "HTTPMockServer", targets: ["HTTPMockServer"]) ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.59.0")
    ],
    targets: [
        .target(
            name: "HTTPMockServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ]),
        .testTarget(
            name: "HTTPMockServerTests",
            dependencies: ["HTTPMockServer"]),
    ]
)
