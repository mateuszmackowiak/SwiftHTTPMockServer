// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HTTPMockServer",
    products: [ .library(name: "HTTPMockServer", targets: ["HTTPMockServer"]) ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.27.0")
    ],
    targets: [
        .target(
            name: "HTTPMockServer",
            dependencies: [ .product(name: "NIOHTTP2", package: "swift-nio-http2") ]),
        .testTarget(
            name: "HTTPMockServerTests",
            dependencies: ["HTTPMockServer"]),
    ]
)
