import BagIdSDK
import SwiftUI

/// What the map settings need to open the managed BLE flow (disable tracking clears the tag first).
struct MapFlowManagedBleLaunch {
    let apiBaseUrl: String
    let sourceAppKey: String
    let federatedToken: String
    let useMockBle: Bool
}

struct ManagedClearRequest: Identifiable {
    let id = UUID()
    let payloadJson: String
}

struct MapFlowNetworkView: View {
    let device: MapDevice
    var managedBle: MapFlowManagedBleLaunch?
    let onBack: () -> Void
    let onViewInMap: () -> Void
    var onClose: (() -> Void)?
    var onConsentChanged: (TrackingConsentView) -> Void

    @State private var consent: TrackingConsentView?
    @State private var errorText: String?
    @State private var busy = false
    @State private var clearRequest: ManagedClearRequest?

    /// `initialConsent` — consent the settings screen already read; shown immediately, refreshed in the background.
    init(
        device: MapDevice,
        managedBle: MapFlowManagedBleLaunch? = nil,
        initialConsent: TrackingConsentView? = nil,
        onConsentChanged: @escaping (TrackingConsentView) -> Void = { _ in },
        onBack: @escaping () -> Void,
        onViewInMap: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.device = device
        self.managedBle = managedBle
        self.onConsentChanged = onConsentChanged
        self.onBack = onBack
        self.onViewInMap = onViewInMap
        self.onClose = onClose
        _consent = State(initialValue: initialConsent)
    }

    private var consentLoading: Bool { device.consentManagementAllowed && consent == nil }

    private var guid: String { device.deviceGuid ?? device.id }

    private var state: DeviceNetworkState {
        DeviceSettingsStateKt.deviceNetworkState(
            bagidModel: device.bagidModel,
            trackingMethod: device.trackingMethod,
            consentManagementAllowed: device.consentManagementAllowed,
            consent: consent,
            activeLockHeldByCaller: device.isWithYou
        )
    }

    private var disableTrackingEnabled: Bool {
        device.consentManagementAllowed && device.isWithYou && state.sharedActive
    }

    private var timeline: NetworkTimelinePresentation? {
        guard let consent else { return nil }
        return DeviceSettingsStateKt.networkTimelinePresentation(consent: consent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapFlowSettingsChrome.closeBar(onClose: onClose ?? onViewInMap)
                MapFlowSettingsChrome.deviceHeader(device: device)
                MapFlowSettingsChrome.actionButton(
                    title: "View in map",
                    fill: MapFlowTheme.accent,
                    text: MapFlowTheme.onPrimary,
                    border: nil,
                    action: onViewInMap
                )
                .padding(.top, 4)
                VStack(spacing: 0) {
                    MapFlowSettingsChrome.networkCardTitle()
                    Divider().padding(.leading, 16)
                    MapFlowSettingsChrome.networkBadgeRow(
                        title: "Shared Network",
                        active: state.sharedActive,
                        loading: consentLoading
                    )
                    if let title = state.personalTitle {
                        Divider().padding(.leading, 16)
                        MapFlowSettingsChrome.networkBadgeRow(
                            title: title,
                            active: state.personalActive,
                            loading: consentLoading
                        )
                    }
                    if !consentLoading, let info = state.infoLine {
                        MapFlowSettingsChrome.infoCallout(info)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                MapFlowSettingsChrome.actionButton(
                    title: busy ? "Disable tracking…" : "Disable tracking",
                    fill: MapFlowSettingsChrome.stopRose,
                    text: .black,
                    border: MapFlowSettingsChrome.stopRed,
                    enabled: disableTrackingEnabled && !busy,
                    action: disableTracking
                )
                .padding(.top, 8)
                if let timeline {
                    MapFlowSettingsChrome.sectionTitle("Tracking", systemImage: nil)
                    MapFlowNetworkTimelineView(presentation: timeline)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
                        .padding(.horizontal, 20)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(MapFlowSettingsChrome.stopRed)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                MapFlowSettingsChrome.actionButton(
                    title: "Back",
                    fill: .white,
                    text: MapFlowTheme.onLight,
                    border: Color(red: 0.8, green: 0.8, blue: 0.8),
                    action: onBack
                )
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(MapFlowSettingsChrome.settingsBackground.ignoresSafeArea())
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
                        finishDisableTracking(clearResultJson: json)
                    }
                )
            }
        }
        .task(id: guid) {
            guard device.consentManagementAllowed else { return }
            do {
                let outcome = try await BagIdSdk.shared.readTrackingConsent(deviceGuid: guid)
                if let failure = outcome.failure {
                    // Keep a value we already had; only fall back to "off" when nothing is known.
                    if consent == nil { consent = MapFlowSettingsChrome.trackingConsentOff }
                    errorText = failure.message
                } else if let read = outcome.consent {
                    consent = read
                    onConsentChanged(read)
                    errorText = nil
                }
            } catch {
                if consent == nil { consent = MapFlowSettingsChrome.trackingConsentOff }
                errorText = "Couldn't read tracking for this bag."
            }
        }
    }

    /// Withdraw consent first, then connect + clear the tag through the managed flow.
    /// Consent must go first: the clear ends with `ebt-unlocks`, after which the backend rejects consent changes.
    /// No BLE target (or no launch context) → withdraw only.
    private func disableTracking() {
        guard disableTrackingEnabled, !busy else { return }
        busy = true
        errorText = nil
        withdrawConsent { startClearIfPossible() }
    }

    private func startClearIfPossible() {
        if managedBle != nil,
           let payload = DisableTrackingClearKt.disableTrackingClearPayloadJson(
               bleDeviceId: device.bleDeviceId,
               advertisedUniqueId: device.uniqueDeviceId
           ) {
            clearRequest = ManagedClearRequest(payloadJson: payload)
        } else {
            busy = false
        }
    }

    private func finishDisableTracking(clearResultJson: String) {
        // == rather than switch: compiles whether the Kotlin enum is bridged as a Swift enum (SKIE)
        // or as a plain class (stale framework), where a switch can't be proven exhaustive.
        let outcome = DisableTrackingClearKt.disableTrackingClearOutcome(resultJson: clearResultJson)
        if outcome == .failed {
            errorText = DisableTrackingClearKt.DISABLE_TRACKING_CLEAR_FAILED_MESSAGE
        }
        busy = false
    }

    /// Runs `onWithdrawn` only when consent was withdrawn; otherwise shows the error and stops.
    private func withdrawConsent(onWithdrawn: @escaping () -> Void) {
        busy = true
        Task {
            var withdrawn = false
            do {
                let outcome = try await BagIdSdk.shared.disableDeviceTracking(deviceGuid: guid)
                if let failure = outcome.failure {
                    errorText = failure.message
                } else {
                    if let read = outcome.consent {
                        consent = read
                        onConsentChanged(read)
                    }
                    errorText = nil
                    withdrawn = true
                }
            } catch {
                errorText = "Couldn't update this bag."
            }
            if withdrawn {
                onWithdrawn()
            } else {
                busy = false
            }
        }
    }
}

struct MapFlowConsentPrivacyView: View {
    let device: MapDevice
    let onBack: () -> Void
    let onViewInMap: () -> Void
    var onClose: (() -> Void)?
    var onConsentChanged: (TrackingConsentView) -> Void
    /// Shared Location is changed only on the Network screen (Disable tracking withdraws and clears the tag).
    var onManageTracking: () -> Void

    @State private var terms: TermsOfUseView?
    @State private var termsLoaded = false
    @State private var acceptingTerms = false
    @State private var sharingOn: Bool
    /// False until consent is known (handed in or read), so the row never shows a guessed "Off".
    @State private var consentKnown: Bool
    @State private var termsUrl: String?
    @State private var privacyUrl: String?
    @State private var errorText: String?
    @State private var expandedPrivacy: Set<Int> = []

    /// `initialConsent` — consent the settings screen already read; shown immediately, refreshed in the background.
    init(
        device: MapDevice,
        initialConsent: TrackingConsentView? = nil,
        onConsentChanged: @escaping (TrackingConsentView) -> Void = { _ in },
        onManageTracking: @escaping () -> Void = {},
        onBack: @escaping () -> Void,
        onViewInMap: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.device = device
        self.onConsentChanged = onConsentChanged
        self.onManageTracking = onManageTracking
        self.onBack = onBack
        self.onViewInMap = onViewInMap
        self.onClose = onClose
        _sharingOn = State(initialValue: initialConsent?.granted == true)
        _consentKnown = State(initialValue: initialConsent != nil || !device.consentManagementAllowed)
    }

    private var guid: String { device.deviceGuid ?? device.id }

    private var privacyItems: [PrivacyAnswer] {
        DeviceSettingsStateKt.privacyAnswers()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapFlowSettingsChrome.closeBar(onClose: onClose ?? onViewInMap)
                MapFlowSettingsChrome.deviceHeader(device: device)
                MapFlowSettingsChrome.actionButton(
                    title: "View in map",
                    fill: MapFlowTheme.accent,
                    text: MapFlowTheme.onPrimary,
                    border: nil,
                    action: onViewInMap
                )
                .padding(.top, 4)

                VStack(spacing: 0) {
                    consentCardHeader
                    Divider().padding(.leading, 16)
                    termsRow
                    Divider().padding(.leading, 16)
                    sharedLocationRow
                    if !device.consentManagementAllowed {
                        Text("Location consent cannot be changed for this bag on your journey.")
                            .font(.footnote)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }
                    MapFlowSettingsChrome.infoCallout(
                        "If you reject location sharing, your airline will be unable to follow your bag."
                    )
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                MapFlowSettingsChrome.sectionTitle("Privacy", systemImage: nil)
                VStack(spacing: 0) {
                    ForEach(Array(privacyItems.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        privacyAccordionRow(index: index, item: item)
                    }
                    Divider().padding(.leading, 16)
                    Button(action: { open(privacyUrl) }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                            Text("Read Privacy Policy")
                                .font(.subheadline)
                                .foregroundStyle(MapFlowTheme.onLight)
                            Spacer()
                            if privacyUrl != nil {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(privacyUrl == nil)
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: MapFlowTheme.cardRadius))
                .padding(.horizontal, 20)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(MapFlowSettingsChrome.stopRed)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                MapFlowSettingsChrome.actionButton(
                    title: "Back",
                    fill: .white,
                    text: MapFlowTheme.onLight,
                    border: Color(red: 0.8, green: 0.8, blue: 0.8),
                    action: onBack
                )
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .background(MapFlowSettingsChrome.settingsBackground.ignoresSafeArea())
        .task(id: guid) {
            // Independent reads — run together so consent isn't held up behind terms / links.
            async let termsRead = try? BagIdSdk.shared.readTermsOfUse()
            async let linksRead = try? BagIdSdk.shared.legalLinks()
            if device.consentManagementAllowed,
               let outcome = try? await BagIdSdk.shared.readTrackingConsent(deviceGuid: guid) {
                if let failure = outcome.failure {
                    errorText = failure.message
                } else if let consent = outcome.consent {
                    sharingOn = consent.granted
                    onConsentChanged(consent)
                }
            }
            consentKnown = true
            terms = await termsRead
            termsLoaded = true
            if let links = await linksRead {
                termsUrl = links.termsOfUse
                privacyUrl = links.privacyPolicy
            }
        }
    }

    /// Terms acceptance is one-way (there is no withdraw API), so this is a status row, not a switch:
    /// "Accepted", or an Accept button when the current version is not accepted for this travel plan.
    private var termsRow: some View {
        HStack(spacing: 8) {
            Text("Terms of Use")
                .font(.subheadline)
                .foregroundStyle(MapFlowTheme.onLight)
            if termsUrl != nil {
                Button { open(termsUrl) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read Terms of Use")
            }
            Spacer()
            if !termsLoaded || acceptingTerms {
                ProgressView()
                    .controlSize(.small)
            } else if let current = terms {
                if current.accepted {
                    Text("Accepted")
                        .font(.subheadline)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                } else {
                    Button("Accept") { acceptTerms(current) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(MapFlowTheme.accent)
                }
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func acceptTerms(_ current: TermsOfUseView) {
        guard !acceptingTerms else { return }
        acceptingTerms = true
        Task {
            do {
                try await BagIdSdk.shared.acceptTermsOfUse(version: current.version)
                errorText = nil
            } catch {
                errorText = "Couldn't accept the Terms of Use. Please try again."
            }
            if let refreshed = try? await BagIdSdk.shared.readTermsOfUse() {
                terms = refreshed
            }
            acceptingTerms = false
        }
    }

    private var consentCardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
            Text("Consent Management")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Read-only Shared Location status. Turning sharing off lives on the Network screen (Disable tracking),
    /// which also clears the tag; turning it on belongs to check-in. Tappable only when consent may be managed.
    private var sharedLocationRow: some View {
        let manageable = device.consentManagementAllowed && consentKnown
        return Button(action: onManageTracking) {
            HStack(spacing: 8) {
                Text("Shared Location")
                    .font(.subheadline)
                    .foregroundStyle(MapFlowTheme.onLight)
                Spacer()
                if !consentKnown {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(DeviceSettingsStateKt.consentRowValue(granted: sharingOn))
                        .font(.subheadline)
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                    if device.consentManagementAllowed {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!manageable)
        .accessibilityHint(manageable ? "Opens the Network screen" : "")
    }

    @ViewBuilder
    private func privacyAccordionRow(index: Int, item: PrivacyAnswer) -> some View {
        let expanded = expandedPrivacy.contains(index)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded {
                    expandedPrivacy.remove(index)
                } else {
                    expandedPrivacy.insert(index)
                }
            } label: {
                HStack {
                    Text(item.question)
                        .font(.subheadline)
                        .foregroundStyle(MapFlowTheme.onLight)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(item.answer)
                    .font(.footnote)
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
    }

    private func open(_ url: String?) {
        guard let https = SettingsViewsKt.httpsUrlOrNull(value: url),
              let link = URL(string: https) else { return }
        UIApplication.shared.open(link)
    }
}
