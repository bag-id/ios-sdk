// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BagIdSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "BagIdSDK",
            targets: ["BagIdSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BagIdSDK",
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v1.1.0.xcframework.zip",
            checksum: "a9c49a0b2ac5f7fedccb1169a1f7303f6d1fb8ae55e153702bfa841af9f576bb"
        )
    ]
)
