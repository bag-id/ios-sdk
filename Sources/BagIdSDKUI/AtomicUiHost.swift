import BagIdSDK
import SwiftUI
import UIKit

// MARK: - Atomic UI (pre-BLE)
//
// Three host-launched full-screen sections — not managed BLE and not SHOW_MAP:
//   SELECT_TAG_TYPE  — BagID vs Other; optional “don’t show again”
//   SERVICE_INFO     — privacy / terms (needs configure + initialize)
//   PREPARE_TAG      — wake Bluetooth; help is an in-screen sheet, not a host API
//
// The host calls each present* in the order it wants. Wrap a chain in beginAtomicUi /
// endAtomicUi so one cover stays up and sections swap (spinner between them). SUCCESS
// inside a session does not dismiss that cover — the next present* (or managed BLE / map)
// swaps in. CANCELLED / FAILURE dismisses. Leave the cover up after prepare SUCCESS if
// presentManagedBleFlow is next.
//
extension BagIdIosHost {
    /// Opens the full-screen cover used for a host-sequenced atomic chain.
    /// Sections presented while the cover is up swap in place; the airline UI stays hidden until [endAtomicUi].
    @MainActor
    public static func beginAtomicUi(from presenter: UIViewController) async {
        await AtomicUiCover.begin(from: presenter)
    }

    /// Dismisses the cover opened by [beginAtomicUi]. Safe if none is showing.
    /// Waits until the cover has finished dismissing so a following present can succeed.
    @MainActor
    public static func endAtomicUi() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AtomicUiCover.end { continuation.resume() }
        }
    }

    /// Full-screen `SELECT_TAG_TYPE`. No federated session required.
    /// Result `data.tagType` is `bagid` or `other`; `data.rememberChoice` drives later skips.
    @MainActor
    public static func presentSelectTagType(
        from presenter: UIViewController,
        completion: @escaping @MainActor (String) -> Void
    ) {
        presentAtomic(from: presenter, operation: "SELECT_TAG_TYPE", completion: completion) { onResult in
            SelectTagTypeFlowView(onResult: onResult)
        }
    }

    /// Full-screen `SERVICE_INFO` (GDPR duty to inform). Requires API URL, source app key, federated token.
    /// Consent GET/POST are placeholders until a backend contract exists.
    /// If consent is already recorded, returns `SUCCESS` with `data.alreadyRecorded: true` and does not present.
    @MainActor
    public static func presentServiceInfo(
        from presenter: UIViewController,
        apiBaseUrl: String,
        sourceAppKey: String,
        federatedToken: String,
        payloadJson: String? = nil,
        completion: @escaping @MainActor (String) -> Void
    ) {
        if AtomicUiCover.isActive {
            AtomicUiCover.showSpinner()
        }
        Task { @MainActor in
            do {
                let request = ServiceInfoLaunchRequest(
                    apiBaseUrl: apiBaseUrl,
                    sourceAppKey: sourceAppKey,
                    federatedToken: federatedToken,
                    payloadJson: payloadJson
                )
                if let failure = try await AtomicUi.shared.prepareServiceInfoSession(request: request) {
                    finishAtomicResult(failure, operation: "SERVICE_INFO", completion: completion)
                    return
                }
                let decision = try await AtomicUi.shared.resolveServiceInfo()
                switch onEnum(of: decision) {
                case .skipUi(let skip):
                    finishAtomicResult(skip.resultJson, operation: "SERVICE_INFO", completion: completion)
                    return
                case .showUi:
                    break
                }
            } catch {
                finishAtomicResult(
                    atomicPresentFailureJson(operation: "SERVICE_INFO", error: error),
                    operation: "SERVICE_INFO",
                    completion: completion
                )
                return
            }
            presentAtomic(from: presenter, operation: "SERVICE_INFO", completion: completion) { onResult in
                ServiceInfoFlowView(
                    apiBaseUrl: apiBaseUrl,
                    sourceAppKey: sourceAppKey,
                    federatedToken: federatedToken,
                    payloadJson: payloadJson,
                    sessionAlreadyReady: true,
                    onResult: onResult
                )
            }
        }
    }

    /// Full-screen `PREPARE_TAG`. Pass the type from SELECT (or the remembered snapshot).
    /// Help is a sheet inside this screen — there is no `presentTagHelp`. No session required.
    @MainActor
    public static func presentPrepareTag(
        from presenter: UIViewController,
        tagType: AtomicTagType,
        completion: @escaping @MainActor (String) -> Void
    ) {
        presentAtomic(from: presenter, operation: "PREPARE_TAG", completion: completion) { onResult in
            PrepareTagFlowView(tagType: tagType, onResult: onResult)
        }
    }

    /// Presents or swaps one atomic section. If a result arrives before the cover is on screen,
    /// it is held until appear so we do not dismiss a VC that is still presenting.
    @MainActor
    private static func presentAtomic<V: View>(
        from presenter: UIViewController,
        operation: String,
        completion: @escaping @MainActor (String) -> Void,
        makeRoot: (@escaping (String) -> Void) -> V
    ) {
        var delivered = false
        let deliver: @MainActor (String) -> Void = { result in
            guard !delivered else { return }
            delivered = true
            completion(result)
        }

        var didAppear = AtomicUiCover.isActive
        var pendingResult: String?

        let view = makeRoot { result in
            if !didAppear {
                pendingResult = result
                return
            }
            finishAtomicResult(result, operation: operation, completion: deliver)
        }

        AtomicUiCover.presentOrSwap(from: presenter, content: AnyView(view)) { appeared in
            guard appeared else {
                deliver(atomicPresentFailureJson(
                    operation: operation,
                    message: "No view controller in the window hierarchy."
                ))
                return
            }
            didAppear = true
            if let pending = pendingResult {
                pendingResult = nil
                finishAtomicResult(pending, operation: operation, completion: deliver)
            }
        }
    }

    /// Session SUCCESS keeps the cover (spinner, except after PREPARE so the next BLE search can replace it).
    /// CANCELLED / FAILURE / standalone present dismiss the cover then complete.
    @MainActor
    private static func finishAtomicResult(
        _ json: String,
        operation: String,
        completion: @escaping @MainActor (String) -> Void
    ) {
        let success = atomicResultIsSuccess(json)
        if AtomicUiCover.isSession {
            if success {
                if operation != "PREPARE_TAG" {
                    AtomicUiCover.showSpinner()
                }
                completion(json)
            } else {
                AtomicUiCover.end {
                    completion(json)
                }
            }
            return
        }
        AtomicUiCover.end {
            completion(json)
        }
    }
}

// MARK: - Single cover (swap in place)
//
// One full-screen `UIHostingController`. `session` is true after `beginAtomicUi` until `end`.
// `presentOrSwap` replaces `model.content` (new `.id`) instead of stacking another modal.
// Managed BLE and SHOW_MAP reuse this cover when it is already active.
@MainActor
enum AtomicUiCover {
    private static var model: Model?
    private static weak var viewController: UIViewController?
    private static var session = false

    @MainActor
    final class Model: ObservableObject {
        @Published var content: AnyView
        @Published var token = UUID()

        init() {
            content = AtomicUiCover.coverSpinner
        }

        func setContent(_ view: AnyView) {
            content = view
            token = UUID()
        }
    }

    private struct Root: View {
        @ObservedObject var model: Model
        var body: some View {
            model.content
                .id(model.token)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.ignoresSafeArea())
        }
    }

    static var isActive: Bool {
        viewController?.presentingViewController != nil || viewController?.isBeingPresented == true
    }

    static var isSession: Bool { session && isActive }

    static func begin(from presenter: UIViewController) async {
        session = true
        if isActive {
            showSpinner()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presentCover(from: presenter, content: coverSpinner, animated: true) { ok in
                if !ok { session = false }
                continuation.resume()
            }
        }
    }

    static func showSpinner() {
        model?.setContent(coverSpinner)
    }

    static func presentOrSwap(
        from presenter: UIViewController,
        content: AnyView,
        onPresented: @escaping (Bool) -> Void
    ) {
        if isActive, let model {
            model.setContent(content)
            onPresented(true)
            return
        }
        presentCover(from: presenter, content: content, animated: true, onPresented: onPresented)
    }

    static func end(then: (() -> Void)? = nil) {
        session = false
        let vc = viewController
        model = nil
        viewController = nil
        guard let vc, vc.presentingViewController != nil else {
            then?()
            return
        }
        vc.dismiss(animated: true, completion: then)
    }

    private static var coverSpinner: AnyView {
        AnyView(
            AtomicUiRingSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.ignoresSafeArea())
        )
    }

    private static func presentCover(
        from presenter: UIViewController,
        content: AnyView,
        animated: Bool,
        onPresented: @escaping (Bool) -> Void
    ) {
        guard let host = presentationHost(from: presenter) else {
            onPresented(false)
            return
        }
        let model = Model()
        model.setContent(content)
        self.model = model
        let vc = UIHostingController(rootView: Root(model: model))
        vc.view.backgroundColor = .white
        vc.modalPresentationStyle = .fullScreen
        vc.modalTransitionStyle = .crossDissolve
        viewController = vc
        var finished = false
        let finish: (Bool) -> Void = { ok in
            guard !finished else { return }
            finished = true
            if !ok {
                self.model = nil
                viewController = nil
            }
            onPresented(ok)
        }
        host.present(vc, animated: animated) {
            finish(true)
        }
        DispatchQueue.main.async {
            if vc.presentingViewController == nil, host.presentedViewController !== vc, !vc.isBeingPresented {
                finish(false)
            }
        }
    }

    private static func presentationHost(from presenter: UIViewController) -> UIViewController? {
        var top = presenter
        while let next = top.presentedViewController,
              next.viewIfLoaded?.window != nil,
              !next.isBeingDismissed {
            top = next
        }
        if top.viewIfLoaded?.window != nil, !top.isBeingDismissed {
            return top
        }
        var cursor: UIViewController? = presenter
        while let current = cursor {
            if current.viewIfLoaded?.window != nil, !current.isBeingDismissed {
                return current
            }
            cursor = current.presentingViewController ?? current.parent
        }
        return nil
    }
}

private func atomicResultIsSuccess(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let status = obj["status"] as? String else { return false }
    return status == "SUCCESS"
}

private func atomicPresentFailureJson(operation: String, error: Error) -> String {
    atomicPresentFailureJson(operation: operation, message: error.localizedDescription)
}

private func atomicPresentFailureJson(operation: String, message: String) -> String {
    let escaped = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "{\"status\":\"FAILURE\",\"operation\":\"\(operation)\",\"code\":\"PRESENT_FAILED\",\"message\":\"\(escaped)\"}"
}
