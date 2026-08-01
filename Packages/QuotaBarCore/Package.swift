// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaBarCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .library(name: "QuotaBarCoreFixtures", targets: ["QuotaBarCoreFixtures"]),
        .library(name: "QuotaBarTransport", targets: ["QuotaBarTransport"])
    ],
    targets: [
        .target(name: "QuotaBarCore"),
        .target(name: "QuotaBarCoreFixtures", dependencies: ["QuotaBarCore"]),
        .target(name: "QuotaBarTransport", dependencies: ["QuotaBarCore"]),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore", "QuotaBarCoreFixtures"]
        ),
        .testTarget(
            name: "QuotaBarTransportTests",
            dependencies: ["QuotaBarTransport", "QuotaBarCore", "QuotaBarCoreFixtures"]
        )
    ]
)
