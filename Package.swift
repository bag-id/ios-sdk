// swift-tools-version: 5.9
import PackageDescription

/// Public SPM distribution: https://github.com/bag-id/ios-sdk
///
/// Products:
///   BagIdSDK   — KMP XCFramework (binary)
///   BagIdSDKUI — SwiftUI host UI (sources). Depends on BagIdSDK + Google Maps.
let package = Package(
    name: "BagIdSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "BagIdSDK",
            targets: ["BagIdSDK"]
        ),
        .library(
            name: "BagIdSDKUI",
            targets: ["BagIdSDKUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "9.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "BagIdSDK",
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v1.2.2.xcframework.zip",
            checksum: "5d7ebece4f76f995052557d3efa2aeb6c3ab0030900cfdac6b39642202989c07"
        ),
        .target(
            name: "BagIdSDKUI",
            dependencies: [
                "BagIdSDK",
                .product(name: "GoogleMaps", package: "ios-maps-sdk"),
            ],
            path: "Sources/BagIdSDKUI",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
