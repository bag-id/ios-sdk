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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v2.0.0.xcframework.zip",
            checksum: "76b82c6a69b51b89fd5fd09000b82fcd8dbf0cdfd9feed9afe8cb04320082e74"
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
