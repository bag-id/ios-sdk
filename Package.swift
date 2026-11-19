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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v3.0.1.xcframework.zip",
            checksum: "3380e5cd0625c6ae6b2ec9b4b9d653dadcdc01b952618b06ff8bd6b0563b615d"
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
