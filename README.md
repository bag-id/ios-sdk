# BagID iOS SDK

Swift Package Manager distribution of the **BagID SDK** — the iOS half of the
BagID cross-platform SDK for discovering BagID devices over BLE, connecting,
sending ticket payloads, clearing the display, and reading battery/firmware
data.

This repository hosts only the `Package.swift` manifest. The actual binary is
delivered as a pre-built `XCFramework` hosted on BagID's public blob storage
and pulled in by SPM via `.binaryTarget`.

> This repo exists purely so Xcode and SPM can resolve the iOS artifact.

## Requirements

- iOS 14.0+
- Xcode 14+
- Swift 5.7+

## Installation

### Xcode

1. **File → Add Package Dependencies…**
2. Enter the repository URL:
   ```
   https://github.com/bag-id/ios-sdk
   ```
3. Choose a version rule (we recommend **Up to Next Major**) and add the
   `BagIdSDK` library to your target.

### Package.swift

Add the package to your `dependencies`:

```swift
dependencies: [
    .package(url: "https://github.com/bag-id/ios-sdk", from: "1.0.0")
]
```

…and the product to the targets that need it:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "BagIdSDK", id: "bagid-ios-sdk")
    ]
)
```

## Versioning

This repository uses Git tags that mirror the SDK release version:

- Tag `v1.0.0` → BagID SDK `1.0.0`
- Each tag pins `Package.swift` to a specific XCFramework URL and SHA-256
  checksum, so resolved versions are reproducible and tamper-evident.

Pre-release versions (e.g. `v1.1.0-beta.1`) follow SemVer pre-release rules
and are only resolved when explicitly requested in your version range.

## Releases

The XCFramework hosted by this package is produced from the private source
repository. Each release:

1. Builds `BagIdSDK.xcframework` from the KMP source.
2. Zips it and uploads to Azure Blob Storage under a versioned name
   (`BagIdSDK-vX.Y.Z.xcframework.zip`).
3. Updates `Package.swift` in this repo with the new URL + checksum.
4. Tags `vX.Y.Z` and pushes.

## Support

- **Documentation:** https://dev.bagid.com
- **Issues:** https://github.com/bag-id/ios-sdk/issues
- **Security:** report privately to `development@bagid.no` — please do not file
  public issues for vulnerabilities.

## License

Copyright © BagID AS. All rights reserved.

The BagID SDK is distributed under a commercial license. Use of the SDK
requires a valid API key and agreement with BagID's terms of service.
