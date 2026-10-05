import BagIdSDK
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
    @State private var navigationPath = NavigationPath()
    @State private var highlightedDeviceId: String?
    @State private var mapFocusDeviceId: String?
    @State private var mapFocusGeneration = 0
    @State private var refreshingDeviceId: String?
    @State private var sheetHeight: CGFloat?
    @State private var sheetDragStartHeight: CGFloat?
    @State private var showSatellite = true
    @State private var theme = ManagedBleFlowTheme.snapshot()

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
                    Button("Close") { onResult(loadError) }
                }
                .padding()
            } else {
                mapContent
            }
        }
        .task { await bootstrap() }
    }

    private var mapContent: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                mapHeader
                GeometryReader { geo in
                    let minH = min(168, max(148, geo.size.height * 0.26))
                    let midH = min(318, max(260, geo.size.height * 0.48))
                    let maxH = max(midH, geo.size.height * 0.86)
                    let listHeight = min(max(sheetHeight ?? midH, minH), maxH)
                    ZStack(alignment: .bottom) {
                        mapLayer
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        satelliteToggle
                            .padding(.trailing, 16)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.bottom, listHeight)
                        addedBagsCard(minH: minH, midH: midH, maxH: maxH)
                            .frame(height: listHeight, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.cardBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { deviceId in
                if let device = devices.first(where: { $0.id == deviceId }) {
                    MapFlowDeviceSettingsView(device: device) {
                        onResult(mapFlowCancelledResultJson(message: "cancelled"))
                    }
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
    private var mapLayer: some View {
        if let key = iosMapsKey, !key.isEmpty {
            MapFlowGoogleMapView(
                devices: devices,
                mapsApiKey: key,
                focusDeviceId: mapFocusDeviceId,
                selectedDeviceId: highlightedDeviceId,
                focusGeneration: mapFocusGeneration,
                showSatellite: showSatellite,
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

    private func addedBagsCard(minH: CGFloat, midH: CGFloat, maxH: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHandle(minH: minH, midH: midH, maxH: maxH)
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
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
        )
    }

    private func sheetHandle(minH: CGFloat, midH: CGFloat, maxH: CGFloat) -> some View {
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
        .gesture(sheetDrag(minH: minH, midH: midH, maxH: maxH))
        .accessibilityLabel("Resize device list")
        .accessibilityAddTraits(.isButton)
    }

    private func sheetDrag(minH: CGFloat, midH: CGFloat, maxH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if sheetDragStartHeight == nil {
                    sheetDragStartHeight = sheetHeight ?? midH
                }
                let next = (sheetDragStartHeight ?? midH) - value.translation.height
                sheetHeight = min(maxH, max(minH, next))
            }
            .onEnded { value in
                let start = sheetDragStartHeight ?? sheetHeight ?? midH
                sheetDragStartHeight = nil
                let predicted = start - value.predictedEndTranslation.height
                let snapped: CGFloat
                if predicted < (minH + midH) / 2 {
                    snapped = minH
                } else if predicted > (midH + maxH) / 2 {
                    snapped = maxH
                } else {
                    snapped = midH
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    sheetHeight = snapped
                }
            }
    }

    @MainActor
    private func showDeviceOnMap(deviceId: String) async {
        refreshingDeviceId = deviceId
        defer { refreshingDeviceId = nil }
        do {
            devices = try await loadMapDevices()
            highlightedDeviceId = deviceId
            mapFocusDeviceId = deviceId
            mapFocusGeneration += 1
        } catch {
            loadError = mapFlowCancelledResultJson(message: error.localizedDescription)
        }
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
            iosMapsKey = try await resolveMapFlowIosMapsKey()
            if highlightedDeviceId == nil {
                highlightedDeviceId = devices.first?.id
            }
            loading = false
        } catch {
            loading = false
            loadError = mapFlowCancelledResultJson(message: error.localizedDescription)
        }
    }

    @MainActor
    private func loadMapDevices() async throws -> [MapDevice] {
        MapFlowRunner.shared.deviceMapDataSource = MockDeviceMapDataSource()
        return try await loadMapFlowDevices()
    }
}

private struct MapFlowAddedBagRow: View {
    let device: MapDevice
    let isHighlighted: Bool
    let isRefreshing: Bool
    let onShowOnMap: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                            Text(MapFlowDeviceChrome.nameEmoji(for: device))
                                .font(.footnote)
                            Text(device.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MapFlowTheme.onLight)
                        }
                        Text("\(device.proximityLabel) · \(device.lastSeenLabel)")
                            .font(.footnote.weight(device.isWithYou ? .semibold : .regular))
                            .foregroundStyle(
                                device.isWithYou
                                    ? Color(red: 0 / 255, green: 132 / 255, blue: 80 / 255)
                                    : MapFlowTheme.onLight
                            )
                        Text(device.airportLabel)
                            .font(.caption)
                            .foregroundStyle(MapFlowTheme.onLight)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onOpenSettings) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MapFlowTheme.onLight)
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Device settings")
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: 1)
        )
    }

    private var rowBorderColor: Color {
        if isHighlighted {
            return MapFlowTheme.accent
        }
        return Color(white: 0.86)
    }
}
