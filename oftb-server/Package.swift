// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "oftb-server",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "oftb-server",
            targets: ["oftb-server"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.93.0"),
        .package(name: "OFTBShared", path: "OFTBShared")
    ],
    targets: [
        .executableTarget(
            name: "oftb-server",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "OFTBShared"
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
