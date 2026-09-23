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
            url: "https://bagidpublic.blob.core.windows.net/ios-sdk/BagIdSDK-v1.2.1.xcframework.zip",
            checksum: "ac0ea45030be142829f80f2b967ef446958532ea2ef14fc3d3ff8f427a33ef31"
        )
    ]
)
