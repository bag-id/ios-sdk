import BagIdSDK
import SwiftUI
import UIKit

struct MapFlowDeviceSettingsView: View {
    let device: MapDevice
    var managedBle: MapFlowManagedBleLaunch?
    var lostModeOn: Bool = false
    var onLostModeChanged: (Bool) -> Void = { _ in }
    var onTrackingLiveChanged: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var keepLockOn = false
    @State private var lostModeError: String?
    @State private var savingLostMode = false
    @State private var page: SettingsDestination?
    /// Full consent read once here and handed to Network / Consent so they open with the right state.
    /// nil = not read yet (or consent APIs not allowed for this caller).
    @State private var consent: TrackingConsentView?
    @State private var clearRequest: ManagedClearRequest?
    @State private var clearMessage: String?

    private var consentGranted: Bool { consent?.granted == true }
    private var consentLoading: Bool { device.consentManagementAllowed && consent == nil }
    /// Live from this screen's consent once read (it changes on Network / Consent), else the map's value.
    private var trackingLive: Bool {
        guard let consent else { return device.trackingLive }
        return MapDeviceListPresentationKt.mapTrackingLive(lockHeldByCaller: device.isWithYou, consent: consent)
    }
    private var liveDevice: MapDevice { device.withTrackingLive(live: trackingLive) }

    private let stopRed = Color(red: 196 / 255, green: 57 / 255, blue: 57 / 255)

    var body: some View {
        Group {
            if page == .network {
                MapFlowNetworkView(
                    device: liveDevice,
                    managedBle: managedBle,
                    initialConsent: consent,
                    onConsentChanged: { consent = $0 },
                    onBack: { page = nil },
                    onViewInMap: { dismiss() },
                    onClose: { dismiss() }
                )
            } else if page == .consent {
                MapFlowConsentPrivacyView(
                    device: liveDevice,
                    initialConsent: consent,
                    onConsentChanged: { consent = $0 },
                    onManageTracking: { page = .network },
                    onBack: { page = nil },
                    onViewInMap: { dismiss() },
                    onClose: { dismiss() }
                )
            } else if page == .appSettings {
                MapFlowAppSettingsView(
                    device: liveDevice,
                    onBack: { page = nil },
                    onViewInMap: { dismiss() },
                    onClose: { dismiss() }
                )
            } else {
                settingsBody
            }
        }
        .background(Color(red: 244 / 255, green: 244 / 255, blue: 246 / 255).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $clearRequest) { request in
            if let managedBle {
                ManagedBleFlowView(
                    apiBaseUrl: managedBle.apiBaseUrl,
                    sourceAppKey: managedBle.sourceAppKey,
                    federatedToken: managedBle.federatedToken,
                    operation: "CLEAR",
                    payloadJson: request.payloadJson,
                    useMockBle: managedBle.useMockBle,
                    onResult: { json in
                        clearRequest = nil
                        let outcome = DisableTrackingClearKt.disableTrackingClearOutcome(resultJson: json)
                        clearMessage = DisableTrackingClearKt.clearTagResultMessage(outcome: outcome)
                    }
                )
            }
        }
        .onChange(of: trackingLive) { live in
            if live != device.trackingLive { onTrackingLiveChanged(live) }
        }
        .task(id: device.id) {
            keepLockOn = lostModeOn
            guard device.consentManagementAllowed else { return }
            let guid = device.deviceGuid ?? device.id
            do {
                let outcome = try await BagIdSdk.shared.readTrackingConsent(deviceGuid: guid)
                if outcome.failure == nil, let read = outcome.consent {
                    consent = read
                } else if consent == nil {
                    consent = MapFlowSettingsChrome.trackingConsentOff
                }
            } catch {
                if consent == nil { consent = MapFlowSettingsChrome.trackingConsentOff }
            }
        }
    }

    private var settingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                smallActionButton(
                    title: "View in map",
                    fill: .black,
                    text: .white,
                    border: nil,
                    action: { dismiss() }
                )
                settingsCard
                if let clearTagPayload {
                    smallActionButton(
                        title: "Clear tag",
                        fill: .white,
                        text: MapFlowTheme.onLight,
                        border: Color(red: 0.8, green: 0.8, blue: 0.8),
                        action: {
                            clearMessage = nil
                            clearRequest = ManagedClearRequest(payloadJson: clearTagPayload)
                        }
                    )
                    if let clearMessage {
                        Text(clearMessage)
                            .font(.footnote)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
                            .padding(.horizontal, 20)
                    }
                }
                if device.callerIsOwner {
                    section(title: "Lost or Missing BagID") {
                        lostCard
                    }
                }
                section(title: "Help and Support") {
                    helpCard
                }
            }
            .padding(.bottom, 28)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MapFlowDeviceChrome.iconCircleFill(isHighlighted: true))
                        .frame(width: 56, height: 56)
                    MapFlowBagIdGlyph(maxSide: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(MapFlowTheme.onLight)
                        Image(systemName: "pencil")
                            .font(.footnote)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
                        if trackingLive {
                            MapFlowLiveBadge()
                                .padding(.leading, 2)
                        }
                    }
                    Text(device.modelName)
                        .font(.footnote)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                    Text(serialLine)
                        .font(.caption)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    private var serialLine: String {
        let sn = device.serialNumber
        if sn.lowercased().hasPrefix("s/n") { return sn }
        return "S/N \(sn)"
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button { page = .network } label: {
                settingsRow(icon: "wifi", title: "Network", value: networkRow, loading: consentLoading)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)
            Button { page = .consent } label: {
                settingsRow(icon: "lock.shield", title: "Consent & Privacy", value: consentRow, loading: consentLoading)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 52)
            Button { page = .appSettings } label: {
                settingsRow(icon: "gearshape", title: "Settings", value: nil)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
        .padding(.horizontal, 20)
    }

    /// "Clear tag" only once tracking is known to be off — never while the bag is shared/tracked.
    /// nil hides the button (consent still loading, tracking on, or no BLE target / launch context).
    private var clearTagPayload: String? {
        guard managedBle != nil, !consentLoading, !networkState.sharedActive else { return nil }
        return DisableTrackingClearKt.disableTrackingClearPayloadJson(
            bleDeviceId: device.bleDeviceId,
            advertisedUniqueId: device.uniqueDeviceId
        )
    }

    private var networkState: DeviceNetworkState {
        DeviceSettingsStateKt.deviceNetworkState(
            bagidModel: device.bagidModel,
            trackingMethod: device.trackingMethod,
            consentManagementAllowed: device.consentManagementAllowed,
            consent: consent,
            activeLockHeldByCaller: device.isWithYou
        )
    }

    private var networkRow: String? {
        consentLoading ? nil : networkState.rowValue
    }

    private var consentRow: String? {
        consentLoading ? nil : DeviceSettingsStateKt.consentRowValue(granted: consentGranted)
    }

    private func settingsRow(icon: String, title: String, value: String?, loading: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
            if loading {
                ProgressView()
                    .controlSize(.small)
            } else if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var lostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If your bag is lost, keep the lock on so your airline can help trace it.")
                .font(.footnote)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
            HStack {
                Text("Keep lock on for now")
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { keepLockOn },
                    set: { enabled in
                        let previous = keepLockOn
                        keepLockOn = enabled
                        lostModeError = nil
                        Task { await persistLostMode(enabled, rollback: previous) }
                    }
                ))
                    .labelsHidden()
                    .tint(MapFlowTheme.accent)
                    .disabled(savingLostMode)
            }
            if let lostModeError {
                Text(lostModeError)
                    .font(.footnote)
                    .foregroundStyle(stopRed)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
    }

    private func persistLostMode(_ enabled: Bool, rollback: Bool) async {
        savingLostMode = true
        defer { savingLostMode = false }
        let guid = device.deviceGuid ?? device.id
        do {
            if let failure = try await BagIdSdk.shared.setDeviceLostMode(deviceGuid: guid, enabled: enabled) {
                keepLockOn = rollback
                lostModeError = failure.message
                return
            }
            onLostModeChanged(enabled)
        } catch {
            keepLockOn = rollback
            lostModeError = "Couldn't update lost mode."
        }
    }

    private var helpCard: some View {
        VStack(spacing: 14) {
            helpRow("Device Support", "BagID")
            helpRow("Journey Support", "Contact your airline")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
    }

    private func helpRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                .accessibilityLabel("Opens in a new tab")
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
            content()
        }
        .padding(.horizontal, 20)
    }

    private func smallActionButton(
        title: String,
        fill: Color,
        text: Color,
        border: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(fill, in: RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: MapFlowTheme.cornerRadius)
                            .stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

private enum SettingsDestination {
    case network
    case consent
    case appSettings
}
