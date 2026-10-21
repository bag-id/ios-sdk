import BagIdSDK
import CoreLocation
import SwiftUI

/// iOS SHOW_MAP atomic UI — map + Added BagIDs list + device settings.
struct MapFlowView: View {
    let apiBaseUrl: String
    let sourceAppKey: String
    let federatedToken: String
    let payloadJson: String?
    let useMockMap: Bool
    let onResult: (String) -> Void

    @State private var devices: [MapDevice] = []
    @State private var iosMapsKey: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var loadErrorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var highlightedDeviceId: String?
    @State private var mapFocusDeviceId: String?
    @State private var mapFocusGeneration = 0
    @State private var refreshingDeviceId: String?
    @State private var sheetHeight: CGFloat?
    @State private var showSatellite = true
    @State private var theme = ManagedBleFlowTheme.snapshot()
    @State private var lostModeById: [String: Bool] = [:]
    @Environment(\.scenePhase) private var scenePhase

    /// Latest positions every 15 s while the map (not settings) is on screen and the app is active.
    private static let locationRefreshNanos: UInt64 = 15_000_000_000
    private var autoRefreshActive: Bool {
        !loading && loadError == nil && navigationPath.isEmpty && scenePhase == .active
    }

    var body: some View {
        Group {
            if loading {
                AtomicUiRingSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.cardBackground.ignoresSafeArea())
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("Unable to open map")
                        .font(.headline)
                    if let loadErrorMessage {
                        Text(loadErrorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.75))
                    }
                    Button("Close") { onResult(loadError) }
                }
                .padding()
            } else {
                mapContent
            }
        }
        .task { @MainActor in await bootstrap() }
        .task(id: autoRefreshActive) { @MainActor in
            guard autoRefreshActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.locationRefreshNanos)
                if Task.isCancelled { return }
                // Positions only; a failed read keeps the pins and tries again next tick.
                guard let snapshot = try? await MapFlowRunner.shared.loadLocations(useMockMap: useMockMap) else { continue }
                devices = snapshot.applyTo(devices: devices)
            }
        }
    }

    private var mapContent: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                mapHeader
                GeometryReader { geo in
                    let minH = min(168, max(148, geo.size.height * 0.26))
                    let midH = min(318, max(260, geo.size.height * 0.48))
                    let maxH = max(midH, geo.size.height * 0.86)
                    // Snapped height only — the live drag stays inside MapFlowDeviceSheet so the map
                    // (a UIViewRepresentable) isn't re-padded / re-fitted on every drag frame.
                    let listHeight = min(max(sheetHeight ?? midH, minH), maxH)
                    ZStack(alignment: .bottom) {
                        mapLayer(bottomInset: listHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        satelliteToggle
                            .padding(.trailing, 16)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.bottom, listHeight)
                        MapFlowDeviceSheet(
                            height: listHeight,
                            minH: minH,
                            midH: midH,
                            maxH: maxH,
                            onSnap: { sheetHeight = $0 }
                        ) {
                            addedBagsList(hiddenBelow: maxH - listHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.cardBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { deviceId in
                if let device = devices.first(where: { $0.id == deviceId }) {
                    MapFlowDeviceSettingsView(
                        device: device,
                        managedBle: MapFlowManagedBleLaunch(
                            apiBaseUrl: apiBaseUrl,
                            sourceAppKey: sourceAppKey,
                            federatedToken: federatedToken,
                            useMockBle: useMockMap
                        ),
                        lostModeOn: lostModeById[device.id] ?? device.lostMode,
                        onLostModeChanged: { enabled in
                            lostModeById[device.id] = enabled
                        },
                        onTrackingLiveChanged: { live in
                            devices = devices.map { $0.id == device.id ? $0.withTrackingLive(live: live) : $0 }
                        }
                    )
                }
            }
        }
    }

    private var mapHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MapFlowTheme.onLight.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(MapFlowTheme.onLight.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                Spacer()
                Button { onResult(mapFlowCancelledResultJson(message: "cancelled")) } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MapFlowTheme.onLight)
                        .frame(width: 36, height: 36)
                        .background(MapFlowTheme.onLight.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            Text("Your BagID is now traceable!")
                .font(.headline.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(
            Color.white
                .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private func mapLayer(bottomInset: CGFloat) -> some View {
        if let key = iosMapsKey, !key.isEmpty {
            MapFlowGoogleMapView(
                devices: devices,
                mapsApiKey: key,
                focusDeviceId: mapFocusDeviceId,
                selectedDeviceId: highlightedDeviceId,
                focusGeneration: mapFocusGeneration,
                showSatellite: showSatellite,
                bottomInset: bottomInset,
                onSelectDevice: { highlightedDeviceId = $0 }
            )
        } else {
            MapFlowMapUnavailableView()
        }
    }

    private var satelliteToggle: some View {
        Button {
            showSatellite.toggle()
        } label: {
            Image(systemName: showSatellite ? "map.fill" : "globe.americas.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(MapFlowTheme.onLight)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        }
        .accessibilityLabel(showSatellite ? "Show map view" : "Show satellite view")
        .accessibilityAddTraits(.isButton)
    }

    /// `hiddenBelow` — part of the fixed-height sheet that sits off-screen at the current snap,
    /// padded so the last row can still scroll into view.
    private func addedBagsList(hiddenBelow: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(devices, id: \.id) { device in
                    MapFlowAddedBagRow(
                        device: device,
                        isHighlighted: highlightedDeviceId == device.id,
                        isRefreshing: refreshingDeviceId == device.id,
                        onShowOnMap: { Task { await showDeviceOnMap(deviceId: device.id) } },
                        onOpenSettings: { navigationPath.append(device.id) }
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12 + hiddenBelow)
        }
        // Soft edge where rows pass under the header, instead of a hard cut-off.
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
                Color.black
            }
        )
    }

    @MainActor
    private func showDeviceOnMap(deviceId: String) async {
        // Select and fly to the last known position straight away; refresh in the background and
        // only move the map again if the bag's position actually changed.
        let before = devices.first(where: { $0.id == deviceId })
        highlightedDeviceId = deviceId
        if before?.locationAvailable == true {
            focusMap(on: deviceId)
        }
        refreshingDeviceId = deviceId
        defer { if refreshingDeviceId == deviceId { refreshingDeviceId = nil } }
        do {
            let refreshed = try await loadMapDevices()
            if let failure = MapFlowRunner.shared.lastDeviceLoadFailure {
                loadErrorMessage = failure.message
                loadError = mapFlowFailureResultJson(code: failure.code, message: failure.message)
                return
            }
            devices = refreshed
            guard highlightedDeviceId == deviceId,
                  let after = refreshed.first(where: { $0.id == deviceId }), after.locationAvailable
            else { return }
            let moved = before?.locationAvailable != true ||
                before?.latitude != after.latitude || before?.longitude != after.longitude
            if moved { focusMap(on: deviceId) }
        } catch {
            loadErrorMessage = "Couldn't load your bags."
            loadError = mapFlowFailureResultJson(code: "LOAD_FAILED", message: "Couldn't load your bags.")
        }
    }

    private func focusMap(on deviceId: String) {
        mapFocusDeviceId = deviceId
        mapFocusGeneration += 1
    }

    @MainActor
    private func bootstrap() async {
        registerMapFlowIosCredentialsChain()
        if let failureJson = try? await prepareMapFlowSessionOrFailureJson(
            apiBaseUrl: apiBaseUrl,
            sourceAppKey: sourceAppKey,
            federatedToken: federatedToken,
            payloadJson: payloadJson
        ) {
            loading = false
            loadError = failureJson
            return
        }
        do {
            devices = try await loadMapDevices()
            if let failure = MapFlowRunner.shared.lastDeviceLoadFailure {
                loading = false
                loadErrorMessage = failure.message
                loadError = mapFlowFailureResultJson(code: failure.code, message: failure.message)
                return
            }
            iosMapsKey = try await resolveMapFlowIosMapsKey()
            if highlightedDeviceId == nil {
                highlightedDeviceId = devices.first?.id
            }
            loading = false
        } catch {
            loading = false
            loadErrorMessage = "Couldn't load your bags."
            loadError = mapFlowFailureResultJson(code: "LOAD_FAILED", message: "Couldn't load your bags.")
        }
    }

    @MainActor
    private func loadMapDevices() async throws -> [MapDevice] {
        try await MapFlowRunner.shared.loadDevices(useMockMap: useMockMap)
    }
}

private struct MapFlowAddedBagRow: View {
    let device: MapDevice
    let isHighlighted: Bool
    let isRefreshing: Bool
    let onShowOnMap: () -> Void
    let onOpenSettings: () -> Void

    @State private var placeName: String?

    private var locationSummary: String {
        guard device.locationAvailable else { return "No location data available" }
        let parts = [placeName, device.lastSeenLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "No location data available" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onShowOnMap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(MapFlowDeviceChrome.iconCircleFill(isHighlighted: isHighlighted))
                            .frame(width: 48, height: 48)
                        MapFlowBagIdGlyph(maxSide: 26)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(device.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MapFlowTheme.onLight)
                                .lineLimit(1)
                            if device.trackingLive {
                                MapFlowLiveBadge()
                            }
                        }
                        Text(device.modelName)
                            .font(.footnote)
                            .foregroundStyle(MapFlowTheme.onLight.opacity(0.75))
                        if MapFlowDeviceChrome.hasListSerial(device) {
                            Text(MapFlowSettingsChrome.serialLine(for: device))
                                .font(.caption)
                                .foregroundStyle(MapFlowTheme.onLight.opacity(0.55))
                        }
                        Text(locationSummary)
                            .font(device.locationAvailable ? .caption.weight(.medium) : .caption)
                            .foregroundStyle(locationColor)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .padding(.trailing, 4)
                // Whole card (padding + empty space) selects the bag, not just the text and icon.
                .contentShape(Rectangle())
            }
            .buttonStyle(MapFlowRowPressStyle())
            .task(id: locationLookupKey) {
                guard device.locationAvailable else {
                    placeName = nil
                    return
                }
                placeName = await MapFlowPlaceName.lookup(
                    latitude: device.latitude,
                    longitude: device.longitude
                )
            }

            Rectangle()
                .fill(Color(white: 0.9))
                .frame(width: 1)
                .padding(.vertical, 14)
            Button(action: onOpenSettings) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MapFlowTheme.onLight)
                    .frame(width: 52)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MapFlowRowPressStyle())
            .accessibilityLabel("Device settings")
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: 1)
        )
    }

    private var locationColor: Color {
        guard device.locationAvailable,
              let color = MapFlowFreshnessColor.color(lastSeenAt: device.lastSeenAt)
        else { return MapFlowTheme.onLight.opacity(0.55) }
        return color
    }

    private var locationLookupKey: String {
        guard device.locationAvailable else { return "\(device.id):none" }
        return "\(device.id):\(device.latitude):\(device.longitude)"
    }

    private var rowBorderColor: Color {
        if isHighlighted {
            return MapFlowTheme.accent
        }
        return Color(white: 0.86)
    }
}

/// Light pressed-state tint so a tap on the row or arrow gives immediate feedback.
private struct MapFlowRowPressStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.black.opacity(configuration.isPressed ? 0.05 : 0))
    }
}

private enum MapFlowPlaceName {
    static func lookup(latitude: Double, longitude: Double) async -> String? {
        let geocoder = CLGeocoder()
        guard let mark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude)
        ).first else { return nil }
        let primary = mark.areasOfInterest?.first ?? mark.name ?? mark.thoroughfare
        let city = mark.locality ?? mark.administrativeArea
        return MapFlowPlaceName.join(primary, city)
    }

    private static func join(_ primary: String?, _ city: String?) -> String? {
        let place = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let area = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if place.isEmpty { return area.isEmpty ? nil : area }
        if area.isEmpty || place.localizedCaseInsensitiveContains(area) { return place }
        return "\(place), \(area)"
    }
}

/// Bottom "Added BagIDs" sheet. Laid out once at `maxH` and moved with `offset`, so dragging never
/// re-lays out the list or the map underneath; the parent only hears about the final snap height.
private struct MapFlowDeviceSheet<Content: View>: View {
    let height: CGFloat
    let minH: CGFloat
    let midH: CGFloat
    let maxH: CGFloat
    let onSnap: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    /// Local to the sheet so drag frames don't re-render the map. Reset in the same animation as the
    /// snap — a @GestureState would reset to 0 before the spring and make the sheet jump.
    @State private var dragTranslation: CGFloat = 0

    private var liveHeight: CGFloat {
        min(maxH, max(minH, height - dragTranslation))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            handle
            content()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .frame(height: maxH, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
        )
        .offset(y: maxH - liveHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var handle: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color(white: 0.74))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            Text("Added BagIDs")
                .font(.headline)
                .foregroundStyle(MapFlowTheme.onLight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityLabel("Resize device list")
        .accessibilityAddTraits(.isButton)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragTranslation = value.translation.height }
            }
            .onEnded { value in
                let predicted = height - value.predictedEndTranslation.height
                let snapped: CGFloat
                if predicted < (minH + midH) / 2 {
                    snapped = minH
                } else if predicted > (midH + maxH) / 2 {
                    snapped = maxH
                } else {
                    snapped = midH
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    dragTranslation = 0
                    onSnap(snapped)
                }
            }
    }
}
