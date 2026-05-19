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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v0.2.2.xcframework.zip",
            checksum: "4fe23376d4124463bb3499ed5ad7ee0c47532e429d8cccbd85c76e555a3e32fe"
        )
    ]
)
