import BagIdSDK
import SwiftUI
import UIKit

// MARK: - BagIdIosHost
//
// iOS equivalent of Android's BagIdAndroidHost / BagIdRnFacade.
public class BagIdIosHost {

    /// Present the managed BLE flow full-screen from any UIViewController.
    ///
    /// - Parameters:
    ///   - presenter: The presenting UIViewController (topmost VC is found automatically).
    ///   - apiBaseUrl: BagId API base URL (e.g. "https://api.bagid.com").
    ///   - sourceAppKey: `X-Source-App-Key` header value.
    ///   - federatedToken: Federated JWT from the host app's IdP.
    ///   - operation: One of "TRANSFER", "CLEAR", "READ_BATTERY", "READ_FIRMWARE".
    ///   - payloadJson: Optional JSON payload. Schema: `{ schemaVersion, selection?, data }`.
    ///     For TRANSFER, `data` must contain `baggageId` and `journeyId` (UUID strings); `journeyData` is optional (the SDK asks BagID's check-in for it).
    ///   - promptTracking: When `true` and `operation` is `TRANSFER`, show post-transfer tracking
    ///     CTA / consent, then a second transfer with sharing on after Enable Tracking.
    ///     Other operations ignore this (default `false`).
    ///   - tagType: Optional `SELECT_TAG_TYPE` result used for found-device card chrome.
    ///   - useMockBle: When `true`, scan/connect/transfer use fixture peripherals. Default `false`
    ///     (real BLE). Hosts must opt in; the SDK does not mock automatically.
    ///   - completion: Called on the main thread after the flow is dismissed, with the result JSON:
    ///     - `{"status":"SUCCESS","operation":"TRANSFER","data":{...}}`
    ///     - `{"status":"FAILURE","code":"...","message":"..."}`
    ///     - `{"status":"CANCELLED","message":"..."}`
    ///     After a tracking prompt, SUCCESS `data.trackingEnabled` is `true` or `false`.
    ///     When `trackingEnabled` is true and the atomic cover is still up, this method does **not**
    ///     dismiss; the host should call `presentMapFlow` so the map swaps in place. Close of SHOW_MAP
    ///     dismisses the cover.
    @MainActor
    public static func presentManagedBleFlow(
        from presenter: UIViewController,
        apiBaseUrl: String,
        sourceAppKey: String,
        federatedToken: String,
        operation: String,
        payloadJson: String? = nil,
        promptTracking: Bool = false,
        tagType: AtomicTagType? = nil,
        useMockBle: Bool = false,
        completion: @escaping @MainActor (String) -> Void
    ) {
        var delivered = false
        let deliver: @MainActor (String) -> Void = { result in
            guard !delivered else { return }
            delivered = true
            completion(result)
        }

        var dismissThenComplete: ((String) -> Void)?

        let view = ManagedBleFlowView(
            apiBaseUrl: apiBaseUrl,
            sourceAppKey: sourceAppKey,
            federatedToken: federatedToken,
            operation: operation.uppercased(),
            payloadJson: payloadJson,
            promptTracking: promptTracking,
            tagType: tagType,
            useMockBle: useMockBle,
            onResult: { result in
                dismissThenComplete?(result)
            }
        )

        if AtomicUiCover.isActive {
            dismissThenComplete = { result in
                if managedFlowResultOpensMap(result) {
                    AtomicUiCover.showSpinner()
                    deliver(result)
                } else {
                    AtomicUiCover.end { deliver(result) }
                }
            }
            AtomicUiCover.presentOrSwap(from: presenter, content: AnyView(view)) { appeared in
                if !appeared {
                    AtomicUiCover.end {
                        deliver("{\"status\":\"FAILURE\",\"code\":\"PRESENT_FAILED\",\"message\":\"No view controller in the window hierarchy.\"}")
                    }
                }
            }
            return
        }

        let vc = UIHostingController(rootView: view)
        vc.modalPresentationStyle = .fullScreen
        vc.modalTransitionStyle = .crossDissolve

        dismissThenComplete = { [weak vc] result in
            guard let vc else {
                deliver(result)
                return
            }
            vc.dismiss(animated: true) { deliver(result) }
        }

        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }

    /// Present the SHOW_MAP atomic UI (tracking map + device settings) full-screen.
    ///
    /// Same session inputs as managed BLE. Close (X) returns `{"status":"CANCELLED","message":"..."}`.
    /// When an atomic/managed cover is already up (e.g. after tracking setup), the map swaps in place.
    /// - Parameter useMockMap: When `true`, show fixture bags. Default `false` (empty list until session devices exist).
    @MainActor
    public static func presentMapFlow(
        from presenter: UIViewController,
        apiBaseUrl: String,
        sourceAppKey: String,
        federatedToken: String,
        payloadJson: String? = nil,
        useMockMap: Bool = false,
        completion: @escaping @MainActor (String) -> Void
    ) {
        var delivered = false
        let deliver: @MainActor (String) -> Void = { result in
            guard !delivered else { return }
            delivered = true
            completion(result)
        }

        var dismissThenComplete: ((String) -> Void)?

        let view = MapFlowView(
            apiBaseUrl: apiBaseUrl,
            sourceAppKey: sourceAppKey,
            federatedToken: federatedToken,
            payloadJson: payloadJson,
            useMockMap: useMockMap,
            onResult: { result in
                dismissThenComplete?(result)
            }
        )

        if AtomicUiCover.isActive {
            dismissThenComplete = { result in
                AtomicUiCover.end { deliver(result) }
            }
            AtomicUiCover.presentOrSwap(from: presenter, content: AnyView(view)) { appeared in
                if !appeared {
                    AtomicUiCover.end {
                        deliver("{\"status\":\"FAILURE\",\"code\":\"PRESENT_FAILED\",\"message\":\"No view controller in the window hierarchy.\"}")
                    }
                }
            }
            return
        }

        let vc = UIHostingController(rootView: view)
        vc.modalPresentationStyle = .fullScreen
        vc.modalTransitionStyle = .crossDissolve

        dismissThenComplete = { [weak vc] result in
            guard let vc else {
                deliver(result)
                return
            }
            vc.dismiss(animated: true) { deliver(result) }
        }

        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}

/// SUCCESS with tracking opted in keeps the SDK cover up so SHOW_MAP can swap in place.
private func managedFlowResultOpensMap(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (obj["status"] as? String) == "SUCCESS" else { return false }
    return (obj["data"] as? [String: Any])?["trackingEnabled"] as? Bool == true
}
