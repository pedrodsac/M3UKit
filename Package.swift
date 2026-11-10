// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "M3UKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "M3UKit",
            targets: ["M3UKit"]
        ),
        .library(
            name: "XtreamKit",
            targets: ["XtreamKit"]
        ),
    ],
    targets: [
        .target(
            name: "M3UKit"
        ),
        .target(
            name: "XtreamKit",
            dependencies: ["M3UKit"]
        ),
        .testTarget(
            name: "M3UKitTests",
            dependencies: ["M3UKit"]
        ),
        .testTarget(
            name: "XtreamKitTests",
            dependencies: ["XtreamKit", "M3UKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
