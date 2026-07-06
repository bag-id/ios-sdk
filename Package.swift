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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v1.0.0.xcframework.zip",
            checksum: "0c8582d68d5c5839c84327e20c714686546a5a9c63ce8d91321b76f0a6c4242b"
        )
    ]
)
