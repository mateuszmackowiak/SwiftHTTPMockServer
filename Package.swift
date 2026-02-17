// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "HTTPMockServer",
    platforms: [
        .macOS(.v13),
        .iOS(.v15)
    ],
    products: [ .library(name: "HTTPMockServer", targets: ["HTTPMockServer"]) ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.59.0"),
        .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0")
    ],
    targets: [
        .macro(
            name: "HTTPMockServerMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/Macros"
        ),
        .target(
            name: "HTTPMockServer",
            dependencies: [
                "HTTPMockServerMacros",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ]),
        .testTarget(
            name: "HTTPMockServerTests",
            dependencies: ["HTTPMockServer"]),
        .testTarget(
             name: "MacrosTests",
             dependencies: [
                "HTTPMockServer",
               "HTTPMockServerMacros",
               .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
             ]),
    ]
)
