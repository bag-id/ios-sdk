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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v1.2.0.xcframework.zip",
            checksum: "2c6456cc39b7a9e5b9da22e10e313bafdc82067dcba5e8215f07431497f1ab92"
        )
    ]
)
