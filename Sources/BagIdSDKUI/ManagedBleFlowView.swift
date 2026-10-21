import BagIdSDK
import SwiftUI
import UIKit

// MARK: - Flow phase (scan / pick / work / success / optional tracking)

private enum ManagedBlePhase {
    case searching
    case pickDevice
    case working
    case success
    case trackingCta
    case trackingConsent
    case trackingSetup
    case trackingFailed
}

// MARK: - Custody session state (UI mirror of ManagedBleCustodyHost.Prompt from KMP)

private struct CustodySession: Identifiable {
    let id = UUID()
    let hints: CustodyHints
    let attemptIndex: Int
    let maxAttempts: Int
    let lastError: String?
}

// MARK: - ManagedBleFlowView
//
// iOS equivalent of Android ManagedBleFlowActivity / ManagedBleFlowScaffold.
// Present via BagIdIosHost.presentManagedBleFlow(from:...).
//
struct ManagedBleFlowView: View {

    let apiBaseUrl: String
    let sourceAppKey: String
    let federatedToken: String
    /// "TRANSFER" | "CLEAR" | "READ_BATTERY" | "READ_FIRMWARE" | "SEND_NAMETAG"
    let operation: String
    /// Optional JSON payload — schema: { schemaVersion, selection?, data }
    let payloadJson: String?
    /// After TRANSFER success, show CTA → consent → setup. Other operations ignore this.
    let promptTracking: Bool
    /// Device card chrome (BagID vs Other). Nil defaults to BagID.
    let tagType: AtomicTagType?
    /// Fixture BLE when `true`. Default `false` (real radio).
    let useMockBle: Bool
    /// Called once on main thread when the flow completes (result is a JSON string).
    let onResult: (String) -> Void

    init(
        apiBaseUrl: String,
        sourceAppKey: String,
        federatedToken: String,
        operation: String,
        payloadJson: String?,
        promptTracking: Bool = false,
        tagType: AtomicTagType? = nil,
        useMockBle: Bool = false,
        onResult: @escaping (String) -> Void
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.sourceAppKey = sourceAppKey
        self.federatedToken = federatedToken
        self.operation = operation
        self.payloadJson = payloadJson
        self.promptTracking = promptTracking
        self.tagType = tagType
        self.useMockBle = useMockBle
        self.onResult = onResult
        _statusLine = State(initialValue: "")
    }

    // MARK: State

    @State private var phase: ManagedBlePhase = .searching
    @State private var statusLine: String
    @State private var devices: [DiscoveredEbtBleDevice] = []
    @State private var selectedDeviceId: String?
    @State private var pendingResultJson: String?
    @State private var custodySession: CustodySession?
    @State private var custodyRl = ""
    @State private var custodySr = ""
    @State private var custodyTagDisconnected = false
    @State private var custodySubmitPending = false
    @State private var custodyProofSubmitted = false
    @State private var scanPassCount = 0
    @State private var lastTagForCustodyReconnect: DiscoveredEbtBleDevice?
    @State private var didDeliver = false

    @State private var scanTask: Task<Void, Never>?
    @State private var autoSelectTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var guidMatchTask: Task<Void, Never>?
    @State private var trackingSetupAttempt = 0
    @State private var trackingTransferTask: Task<Void, Never>?
    @State private var theme = ManagedBleFlowTheme.snapshot()

    // MARK: Body

    var body: some View {
        let theme = theme
        ZStack {
            phaseBackground.ignoresSafeArea()
            phaseContent(theme: theme)
            if let session = custodySession {
                custodyScreen(session: session, theme: theme)
                    .transition(.opacity)
            }
        }
        .tint(theme.primary)
        .preferredColorScheme(usesLightChrome ? .light : .dark)
        .task { await runFlow() }
        .task { await observeManagedBleCustodyPrompts() }
        .onChange(of: devices.count) { count in
            if allowsManualPick, phase == .searching, count > 0 {
                phase = .pickDevice
            }
        }
        .onDisappear {
            scanTask?.cancel()
            autoSelectTask?.cancel()
            reconnectTask?.cancel()
            guidMatchTask?.cancel()
            trackingTransferTask?.cancel()
            BagIdSdk.shared.resetManagedBleCustodyHost()
        }
    }

    private var usesLightChrome: Bool {
        if custodySession != nil { return true }
        switch phase {
        case .pickDevice, .trackingCta, .trackingConsent: return true
        default: return false
        }
    }

    private var phaseBackground: Color {
        switch phase {
        case .pickDevice, .trackingCta, .trackingConsent:
            return theme.cardBackground
        default:
            return theme.background
        }
    }

    private var allowsManualPick: Bool {
        parsedEnvelope.targetGuid == nil && parsedEnvelope.selection == nil
    }

    private var isTargetedScan: Bool {
        parsedEnvelope.advertisedUniqueId != nil || parsedEnvelope.targetGuid != nil
    }

    private var shouldPromptTracking: Bool {
        promptTracking && operation.uppercased() == "TRANSFER"
    }

    private var isOtherTag: Bool { tagType == .other }

    private var parsedEnvelope: ManagedFlowEnvelope {
        parseManagedFlowPayload(payloadJson)
    }

    // MARK: - Flow content

    @ViewBuilder
    private func phaseContent(theme: ManagedBleFlowTheme) -> some View {
        switch phase {
        case .searching:
            searchingChrome(theme: theme)
        case .pickDevice:
            ManagedBleFoundDevicesView(
                devices: devices,
                selectedDeviceId: selectedDeviceId,
                isOther: isOtherTag,
                errorText: statusLine,
                onSelect: { selectedDeviceId = $0.deviceId },
                onConnect: connectSelectedDevice,
                onSearchAgain: { Task { await startScanPhase() } },
                onBack: cancelFlow,
                onClose: cancelFlow,
                theme: theme
            )
        case .working:
            darkChrome(onClose: cancelFlow) {
                ManagedBleWorkingView(
                    title: workingTitle,
                    hint: workingHint
                )
            }
        case .success:
            darkChrome(onClose: finishTransferWithoutTracking) {
                ManagedBleSuccessView()
            }
            .safeAreaInset(edge: .bottom) {
                AtomicUiBottomButton(title: ManagedBleCopy.next, theme: theme, action: advanceFromSuccess)
            }
        case .trackingCta:
            ManagedBleTrackingCtaView(
                theme: theme,
                onStart: { phase = .trackingConsent },
                onNotNow: finishTransferWithoutTracking
            )
            .overlay(alignment: .top) {
                AtomicUiCloseBar(onLight: true, onClose: finishTransferWithoutTracking)
            }
        case .trackingConsent:
            ManagedBleTrackingConsentView(
                theme: theme,
                onEnable: {
                    trackingSetupAttempt += 1
                    phase = .trackingSetup
                },
                onDecline: finishTransferWithoutTracking
            )
            .overlay(alignment: .top) {
                AtomicUiCloseBar(onLight: true, onClose: finishTransferWithoutTracking)
            }
        case .trackingSetup:
            ManagedBleTrackingSetupView(
                onCancel: cancelTrackingSetup
            )
            .task(id: trackingSetupAttempt) {
                let work = Task { await runTrackingSecondTransfer() }
                trackingTransferTask = work
                await work.value
            }
        case .trackingFailed:
            ManagedBleTrackingFailedView(
                theme: theme,
                onRetry: {
                    trackingSetupAttempt += 1
                    phase = .trackingSetup
                },
                onClose: finishTransferWithoutTracking
            )
        }
    }

    private var workingTitle: String {
        operation.uppercased() == "TRANSFER" ? ManagedBleCopy.transferringTitle : managedBleFlowDisplayTitle(operation)
    }

    private var workingHint: String {
        if operation.uppercased() == "TRANSFER" {
            return ManagedBleCopy.transferringHint
        }
        return statusLine.isEmpty ? ManagedBleCopy.transferringHint : statusLine
    }

    @ViewBuilder
    private func searchingChrome(theme: ManagedBleFlowTheme) -> some View {
        darkChrome(onClose: cancelFlow) {
            VStack(spacing: 20) {
                AtomicUiRingSpinner()
                Text(ManagedBleCopy.searchingTitle)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(ManagedBleCopy.searchingHint)
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
                if postProofReminder {
                    Text("Turn on Bluetooth on your bag tag and hold it near your phone.")
                        .font(.callout)
                        .foregroundStyle(theme.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func darkChrome<Content: View>(
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            AtomicUiCloseBar(onLight: false, onClose: onClose)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }

    private var postProofReminder: Bool {
        custodyProofSubmitted && custodySession == nil
    }

    // MARK: - Custody proof

    private func custodyScreen(session: CustodySession, theme: ManagedBleFlowTheme) -> some View {
        ManagedBleCustodyProofView(
            hints: session.hints,
            attemptIndex: session.attemptIndex,
            maxAttempts: session.maxAttempts,
            lastError: session.lastError,
            tagDisconnected: custodyTagDisconnected,
            waitingForTag: custodySubmitPending,
            recordLocator: $custodyRl,
            surname: $custodySr,
            theme: theme,
            onSubmit: { custodySubmit(session: session) },
            onCancel: { custodyCancel(session: session) }
        )
    }

    // MARK: - Custody actions

    private func custodyCancel(session: CustodySession) {
        custodyTagDisconnected = false
        custodySubmitPending = false
        lastTagForCustodyReconnect = nil
        reconnectTask?.cancel()
        phase = allowsManualPick && !devices.isEmpty ? .pickDevice : .searching
        Task { try? await BagIdSdk.shared.disconnectEbtOrThrow() }
        BagIdSdk.shared.cancelManagedBleCustodyProof()
    }

    private func custodySubmit(session: CustodySession) {
        // Hold the proof until the tag is back — the SDK needs the BLE link right after the proof is accepted.
        if custodyTagDisconnected {
            custodySubmitPending = true
            return
        }
        sendCustodyProof()
    }

    private func sendCustodyProof() {
        custodySubmitPending = false
        custodyProofSubmitted = true
        BagIdSdk.shared.submitManagedBleCustodyProof(
            recordLocator: custodyRl.trimmingCharacters(in: .whitespacesAndNewlines),
            surname: custodySr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Subscribes to KMP [ManagedBleCustodyHost] while `transferTag` suspends for custody proof.
    private func observeManagedBleCustodyPrompts() async {
        for await prompt in BagIdSdk.shared.managedBleCustodyPrompt {
            await MainActor.run {
                if let prompt {
                    custodyRl = ""
                    custodySr = ""
                    custodySession = CustodySession(
                        hints: prompt.hints,
                        attemptIndex: Int(prompt.attemptIndex),
                        maxAttempts: Int(prompt.maxAttempts),
                        lastError: prompt.lastSubmissionError
                    )
                    if let tag = lastTagForCustodyReconnect {
                        startCustodyReconnectObserver(for: tag)
                    }
                } else {
                    custodySession = nil
                    reconnectTask?.cancel()
                    custodyTagDisconnected = false
                    custodySubmitPending = false
                }
            }
        }
    }

    // MARK: - Flow orchestration

    private func cancelFlow() {
        stopScan()
        reconnectTask?.cancel()
        BagIdSdk.shared.resetManagedBleCustodyHost()
        if !useMockBle {
            Task { try? await BagIdSdk.shared.disconnectEbtOrThrow() }
        }
        deliver(json: encode(["status": "CANCELLED", "message": "User cancelled."]))
    }

    private func advanceFromSuccess() {
        if shouldPromptTracking {
            phase = .trackingCta
        } else {
            deliver(json: pendingResultJson ?? encode(["status": "SUCCESS", "operation": operation]))
        }
    }

    private func finishTransferWithoutTracking() {
        let base = pendingResultJson ?? encode(["status": "SUCCESS", "operation": operation])
        deliver(json: shouldPromptTracking ? withTracking(base, enabled: false) : base)
    }

    private func finishTransferWithTracking() {
        let base = pendingResultJson ?? encode(["status": "SUCCESS", "operation": operation])
        deliver(json: withTracking(base, enabled: true))
    }

    private func cancelTrackingSetup() {
        trackingTransferTask?.cancel()
        trackingTransferTask = nil
        finishTransferWithoutTracking()
    }

    private func runTrackingSecondTransfer() async {
        guard let device = lastTagForCustodyReconnect else {
            await MainActor.run { phase = .trackingFailed }
            return
        }
        if useMockBle {
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            await MainActor.run { finishTransferWithTracking() }
            return
        }
        do {
            let json = try await BagIdSdk.shared.reconnectAndTransferWithSharingConsent(
                device: device,
                payloadJson: payloadJson ?? "{}",
                custodyProofCollector: BagIdSdk.shared.managedBleCustodyProofCollector(),
                onStatus: { _ in }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if BagIdSdkSwiftInteropKt.managedFlowTrackingSecondTransferSucceeded(resultJson: json) {
                    finishTransferWithTracking()
                } else {
                    phase = .trackingFailed
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { phase = .trackingFailed }
        }
    }

    private func runFlow() async {
        BagIdSdk.shared.configureWithFederatedToken(
            apiBaseUrl: apiBaseUrl,
            sourceAppKey: sourceAppKey,
            federatedToken: federatedToken,
            theme: BagIdSdk.shared.configuredTheme
        )
        do {
            let initResult = try await BagIdSdk.shared.initialize()
            switch onEnum(of: initResult) {
            case .authenticated:
                break
            case .unavailable(let u):
                let detail = BagIdSdk.shared.bagIdStateSnapshot.lastError
                deliver(json: BagIdSdkSwiftInteropKt.managedFlowInitUnavailableResultJson(reason: u.reason, detail: detail))
                return
            }
        } catch is CancellationError {
            return
        } catch {
            deliver(json: failure(code: "INIT_ERROR", message: error.localizedDescription))
            return
        }

        await startScanPhase()
    }

    private func startScanPhase() async {
        if useMockBle {
            await startMockScanPhase()
            return
        }
        let env = parsedEnvelope
        let targetGuid = env.targetGuid

        await MainActor.run {
            phase = .searching
            scanPassCount += 1
            devices = []
            selectedDeviceId = nil
            statusLine = ""
        }

        stopScan()

        scanTask = Task {
            for await event in BagIdSdk.shared.scanForEbtTags() {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    switch onEnum(of: event) {
                    case .deviceFound(let e):
                        let d = e.device
                        if let idx = devices.firstIndex(where: { $0.deviceId == d.deviceId }) {
                            devices[idx] = d
                        } else {
                            devices.append(d)
                        }
                        if allowsManualPick, phase == .searching {
                            phase = .pickDevice
                        }
                        if let ficr = env.advertisedUniqueId,
                           Self.ficrMatches(d.advertisedUniqueId, ficr),
                           BagIdSdk.shared.ebtBleSnapshot.connectedDevice == nil,
                           guidMatchTask == nil {
                            guidMatchTask = Task {
                                await attemptFicrMatch(device: d)
                            }
                        }
                    case .scanError(let e):
                        statusLine = e.message
                    }
                }
            }
        }

        if env.advertisedUniqueId != nil || targetGuid != nil {
            autoSelectTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs(env) * 1_000_000))
                guard !Task.isCancelled else { return }
                let alreadyConnected = await MainActor.run {
                    BagIdSdk.shared.ebtBleSnapshot.connectedDevice != nil
                }
                if alreadyConnected { return }

                await MainActor.run { stopScanTaskOnly() }

                let snapshot = await MainActor.run { devices }
                let found: DiscoveredEbtBleDevice?
                if let ficr = env.advertisedUniqueId,
                   let hit = snapshot.first(where: { Self.ficrMatches($0.advertisedUniqueId, ficr) }) {
                    found = hit
                } else {
                    found = nil
                }
                if let found {
                    await MainActor.run {
                        phase = .working
                        lastTagForCustodyReconnect = found
                    }
                    await connectAndRun(device: found)
                    return
                }

                await MainActor.run {
                    deliver(json: failure(
                        code: "DEVICE_NOT_FOUND",
                        message: "BagID not found within timeout."
                    ))
                }
            }
        }
    }

    private func startMockScanPhase() async {
        await MainActor.run {
            phase = .searching
            scanPassCount += 1
            devices = []
            selectedDeviceId = nil
            statusLine = ""
        }
        stopScan()
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            let mocks = ManagedBleSimulatorMock.devices(tagType: tagType)
            if isTargetedScan, let first = mocks.first {
                await MainActor.run {
                    devices = mocks
                    phase = .working
                    lastTagForCustodyReconnect = first
                }
                await connectAndRun(device: first)
                return
            }
            await MainActor.run {
                devices = mocks
                phase = .pickDevice
            }
        }
    }

    private func timeoutMs(_ env: ManagedFlowEnvelope) -> Double {
        env.autoSelectTimeoutMs
    }

    private static func compactFicrHex(_ raw: String?) -> String? {
        let hex = (raw ?? "").uppercased().filter { $0.isHexDigit }
        return hex.count == 16 ? hex : nil
    }

    private static func ficrMatches(_ seen: String?, _ target: String?) -> Bool {
        guard let a = compactFicrHex(seen), let b = compactFicrHex(target) else { return false }
        if a == b { return true }
        if a == reverseHexBytes(b) { return true }
        if a == swapU32Words(b) { return true }
        if a == reverseHexBytes(swapU32Words(b)) { return true }
        return false
    }

    private static func reverseHexBytes(_ hex: String) -> String {
        var bytes: [String] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            bytes.append(String(hex[i..<next]))
            i = next
        }
        return bytes.reversed().joined()
    }

    private static func swapU32Words(_ hex: String) -> String {
        guard hex.count == 16 else { return hex }
        let mid = hex.index(hex.startIndex, offsetBy: 8)
        return String(hex[mid...]) + String(hex[..<mid])
    }

    private func attemptFicrMatch(device: DiscoveredEbtBleDevice) async {
        await MainActor.run {
            guidMatchTask = nil
            guard phase == .searching || phase == .pickDevice else { return }
            stopScan()
            phase = .working
            lastTagForCustodyReconnect = device
        }
        await connectAndRun(device: device)
    }

    private func connectSelectedDevice() {
        guard let id = selectedDeviceId,
              let device = devices.first(where: { $0.deviceId == id }) else { return }
        stopScan()
        phase = .working
        Task { await connectAndRun(device: device) }
    }

    private func stopScanTaskOnly() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func stopScan() {
        stopScanTaskOnly()
        autoSelectTask?.cancel()
        autoSelectTask = nil
        guidMatchTask?.cancel()
        guidMatchTask = nil
    }

    private func connectAndRun(device: DiscoveredEbtBleDevice) async {
        await MainActor.run {
            statusLine = "Connecting to \(device.displayLabel())…"
            let op = operation.uppercased()
            if op == "TRANSFER" || op == "SEND_NAMETAG" {
                lastTagForCustodyReconnect = device
            }
        }

        if useMockBle {
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !didDeliver else { return }
                consumeOperationJson(
                    ManagedBleSimulatorMock.successJson(operation: operation, device: device)
                )
            }
            return
        }

        do {
            let resultJson = try await BagIdSdk.shared.connectAndRunBleOperation(
                device: device,
                operation: operation.uppercased(),
                payloadJson: payloadForConnect(),
                custodyProofCollector: BagIdSdk.shared.managedBleCustodyProofCollector(),
                onStatus: { msg in
                    Task { @MainActor in
                        statusLine = msg
                    }
                }
            )
            await MainActor.run { consumeOperationJson(resultJson) }
        } catch {
            await MainActor.run {
                if allowsManualPick {
                    statusLine = error.localizedDescription
                    phase = .pickDevice
                } else {
                    deliver(json: failure(code: "OPERATION_FAILED", message: error.localizedDescription))
                }
            }
        }
    }

    private func consumeOperationJson(_ json: String) {
        guard !didDeliver else { return }
        if managedFlowStatus(json) == "SUCCESS" {
            if operation.uppercased() == "TRANSFER" {
                pendingResultJson = json
                phase = .success
            } else {
                deliver(json: json)
            }
            return
        }
        if allowsManualPick, managedFlowStatus(json) != "CANCELLED" {
            statusLine = managedFlowMessage(json) ?? "Operation failed."
            phase = .pickDevice
            return
        }
        deliver(json: json)
    }

    private func startCustodyReconnectObserver(for device: DiscoveredEbtBleDevice) {
        reconnectTask?.cancel()
        reconnectTask = Task {
            let timeoutMs = Int64(parsedEnvelope.autoSelectTimeoutMs)
            for await state in BagIdSdk.shared.ebtBleDeviceState {
                guard !Task.isCancelled else { break }
                let isConnected = state.connectedDevice?.deviceId.lowercased() == device.deviceId.lowercased()
                await MainActor.run {
                    custodyTagDisconnected = !isConnected
                    if isConnected, custodySubmitPending, custodySession != nil {
                        sendCustodyProof()
                    }
                }
                if !isConnected {
                    _ = try? await BagIdSdk.shared.connectEbtWithScanFallbackOrThrow(
                        device: device,
                        timeoutMs: timeoutMs,
                        onStatus: { _ in }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func deliver(json: String) {
        Task { @MainActor in
            guard !didDeliver else { return }
            didDeliver = true
            stopScan()
            reconnectTask?.cancel()
            trackingTransferTask?.cancel()
            BagIdSdk.shared.resetManagedBleCustodyHost()
            custodySession = nil
            lastTagForCustodyReconnect = nil
            custodyTagDisconnected = false
            custodySubmitPending = false
            onResult(json)
        }
    }

    private func failure(code: String, message: String) -> String {
        encode(["status": "FAILURE", "code": code, "message": message])
    }

    private func withTracking(_ json: String, enabled: Bool) -> String {
        guard var obj = jsonObject(json) else { return json }
        var data = obj["data"] as? [String: Any] ?? [:]
        data["trackingEnabled"] = enabled
        obj["data"] = data
        return encode(obj)
    }

    private func managedFlowStatus(_ json: String) -> String? {
        jsonObject(json)?["status"] as? String
    }

    private func managedFlowMessage(_ json: String) -> String? {
        jsonObject(json)?["message"] as? String
    }

    private func payloadForConnect() -> String {
        let raw = payloadJson ?? "{}"
        guard shouldPromptTracking else { return raw }
        guard var obj = jsonObject(raw) else { return raw }
        var data = obj["data"] as? [String: Any] ?? [:]
        data["sdkKeepConnected"] = true
        obj["data"] = data
        return encode(obj)
    }

    private func jsonObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func encode(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"FAILURE\",\"code\":\"ENCODE_ERROR\"}"
        }
        return str
    }
}
