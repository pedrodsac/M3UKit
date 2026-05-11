// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "M3UKit",
    products: [
        .library(
            name: "M3UKit",
            targets: ["M3UKit"]
        ),
    ],
    targets: [
        .target(
            name: "M3UKit"
        ),
        .testTarget(
            name: "M3UKitTests",
            dependencies: ["M3UKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
