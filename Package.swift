// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BagIdSDK",
    platforms: [
        .iOS(.v14)
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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v0.0.1.xcframework.zip",
            checksum: "1c527759c466f207cd2ce354cfa1ae374b08b2af54313e792a962ac897f3a989"
        )
    ]
)
