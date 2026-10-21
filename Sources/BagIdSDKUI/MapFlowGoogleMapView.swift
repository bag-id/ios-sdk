import BagIdSDK
import CoreLocation
import GoogleMaps
import QuartzCore
import SwiftUI

private enum MapFlowGms {
    private static var didProvideKey = false

    static func provideAPIKeyOnce(_ key: String) {
        guard Thread.isMainThread, !didProvideKey else { return }
        GMSServices.provideAPIKey(key)
        didProvideKey = true
    }
}

/// Hosts [GMSMapView] so the map is created on the main thread after it is in a window.
/// SwiftUI can call `makeUIView` from a cooperative task; Google Maps throws if created there.
final class MapFlowMapHostView: UIView {
    private(set) var mapView: GMSMapView?
    var installMap: (() -> GMSMapView)?
    var onMapReady: ((GMSMapView) -> Void)?
    private var needsApply = true

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView?.frame = bounds
        deliverIfReady()
    }

    func requestApply() {
        needsApply = true
        deliverIfReady()
    }

    private func installIfNeeded() {
        guard Thread.isMainThread, window != nil, mapView == nil, let installMap else { return }
        let created = installMap()
        created.frame = bounds
        created.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(created)
        mapView = created
        deliverIfReady()
    }

    private func deliverIfReady() {
        let minSide = MapFlowMapCamera.clusterPadding * 2
        guard needsApply, let mapView, bounds.width > minSide, bounds.height > minSide else { return }
        needsApply = false
        onMapReady?(mapView)
    }
}

private enum MapFlowMapCamera {
    static let overviewZoom: Float = 5
    static let regionalZoom: Float = 10
    /// Close enough to read the pin, without a street-level slam.
    static let bagFocusZoom: Float = 16
    static let zoomOutDuration: TimeInterval = 2.2
    static let panDuration: TimeInterval = 2.0
    static let zoomInDuration: TimeInterval = 1.8
    static let pauseBetweenSteps: TimeInterval = 0.4
    static let clusterPadding: CGFloat = 72
    static let alreadyFramedZoomSlop: Float = 0.2
}

struct MapFlowGoogleMapView: UIViewRepresentable {
    let devices: [MapDevice]
    let mapsApiKey: String
    var focusDeviceId: String?
    var selectedDeviceId: String?
    var focusGeneration: Int
    var showSatellite: Bool
    var bottomInset: CGFloat = 0
    var onSelectDevice: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MapFlowMapHostView {
        let host = MapFlowMapHostView()
        host.installMap = { self.makeMap(context: context) }
        host.onMapReady = { mapView in self.apply(mapView, context: context) }
        return host
    }

    func updateUIView(_ host: MapFlowMapHostView, context: Context) {
        host.onMapReady = { mapView in self.apply(mapView, context: context) }
        host.requestApply()
    }

    private func makeMap(context: Context) -> GMSMapView {
        MapFlowGms.provideAPIKeyOnce(mapsApiKey)
        let mapView =
            GMSMapView.map(
                withFrame: .zero,
                camera: GMSCameraPosition.camera(
                    withLatitude: 62.0,
                    longitude: 10.7615941,
                    zoom: MapFlowMapCamera.overviewZoom,
                ),
            )
        mapView.isMyLocationEnabled = false
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.mapType = showSatellite ? .hybrid : .normal
        mapView.delegate = context.coordinator
        return mapView
    }

    private func apply(_ mapView: GMSMapView, context: Context) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.apply(mapView, context: context) }
            return
        }
        guard mapView.bounds.width > MapFlowMapCamera.clusterPadding * 2,
              mapView.bounds.height > MapFlowMapCamera.clusterPadding * 2
        else { return }
        let mapType: GMSMapViewType = showSatellite ? .hybrid : .normal
        if mapView.mapType != mapType { mapView.mapType = mapType }
        let firstLayout = context.coordinator.lastDeviceSignature.isEmpty
        let insetChanged = abs(context.coordinator.appliedBottomInset - bottomInset) > 1
        if insetChanged {
            // Only when the device sheet snaps — padding moves the camera's centre, so ease it.
            context.coordinator.appliedBottomInset = bottomInset
            let padding = UIEdgeInsets(top: 12, left: 12, bottom: bottomInset, right: 12)
            if firstLayout {
                mapView.padding = padding
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    mapView.padding = padding
                    mapView.layoutIfNeeded()
                }
            }
        }
        context.coordinator.onSelectDevice = onSelectDevice
        context.coordinator.syncMarkers(on: mapView, devices: devices, selectedDeviceId: selectedDeviceId)
        if firstLayout || (insetChanged && !context.coordinator.hasFocused) {
            context.coordinator.showAllDevicesOverview(on: mapView, devices: devices, animated: !firstLayout)
        } else if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            if let id = focusDeviceId, let device = devices.first(where: { $0.id == id }) {
                context.coordinator.focusOnDevice(
                    on: mapView,
                    device: device,
                    allDevices: devices,
                )
            }
        }
        context.coordinator.lastDeviceSignature = deviceCoordinateSignature(devices)
    }

    private func deviceCoordinateSignature(_ devices: [MapDevice]) -> String {
        devices
            .filter(\.locationAvailable)
            .map {
                let c = MapFlowCoordinates.coordinate(for: $0)
                return "\($0.id):\(c.latitude):\(c.longitude)"
            }
            .joined(separator: "|")
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var lastFocusGeneration: Int = -1
        var lastDeviceSignature: String = ""
        var appliedBottomInset: CGFloat = -1
        var hasFocused = false
        var onSelectDevice: ((String) -> Void)?
        private var markers: [String: GMSMarker] = [:]
        /// What each marker's icon was drawn for, so it is only re-rendered when that changes.
        private var markerLooks: [String: String] = [:]
        private var lastFocusedCoordinate: CLLocationCoordinate2D?
        private var focusSequenceToken = 0

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String {
                onSelectDevice?(id)
            }
            return true
        }

        func syncMarkers(on mapView: GMSMapView, devices: [MapDevice], selectedDeviceId: String?) {
            let pinned = devices.filter { $0.locationAvailable }
            let ids = Set(pinned.map(\.id))
            for (id, marker) in markers where !ids.contains(id) {
                marker.map = nil
                markers.removeValue(forKey: id)
                markerLooks.removeValue(forKey: id)
            }
            for device in pinned {
                let coordinate = MapFlowCoordinates.coordinate(for: device)
                let isSelected = device.id == selectedDeviceId
                let look = "\(isSelected)-\(device.trackingLive)"
                if let marker = markers[device.id] {
                    // Touch only what changed — reassigning icon/position re-renders the pin (flicker).
                    if marker.position.latitude != coordinate.latitude ||
                        marker.position.longitude != coordinate.longitude {
                        marker.position = coordinate
                    }
                    if marker.title != device.displayName { marker.title = device.displayName }
                    let zIndex: Int32 = isSelected ? 2 : 1
                    if marker.zIndex != zIndex { marker.zIndex = zIndex }
                    if markerLooks[device.id] != look {
                        markerLooks[device.id] = look
                        marker.icon = MapFlowBagIdMarkerIcon.markerImage(isPrimary: isSelected, live: device.trackingLive)
                    }
                    if marker.map !== mapView { marker.map = mapView }
                } else {
                    let icon = MapFlowBagIdMarkerIcon.markerImage(isPrimary: isSelected, live: device.trackingLive)
                    markerLooks[device.id] = look
                    let marker = GMSMarker()
                    marker.position = coordinate
                    marker.title = device.displayName
                    marker.icon = icon
                    marker.groundAnchor = MapFlowBagIdMarkerIcon.groundAnchor
                    marker.zIndex = isSelected ? 2 : 1
                    marker.userData = device.id
                    marker.map = mapView
                    markers[device.id] = marker
                }
            }
        }

        /// Zoom out if a bag is off-screen, pan to it, then zoom in so the pin is readable.
        func focusOnDevice(
            on mapView: GMSMapView,
            device: MapDevice,
            allDevices: [MapDevice],
        ) {
            guard device.locationAvailable else { return }
            hasFocused = true
            let target = MapFlowCoordinates.coordinate(for: device)
            let located = allDevices.filter(\.locationAvailable)
            let cluster = MapFlowCoordinates.clusteredDevices(from: located, around: device)
            let bothInView = areAllVisible(cluster, on: mapView)
            let startZoom = mapView.camera.zoom
            var steps: [(GMSCameraUpdate, TimeInterval)] = []

            if !bothInView, cluster.count > 1, let bounds = MapFlowCoordinates.bounds(for: cluster, around: device) {
                let insets = UIEdgeInsets(
                    top: MapFlowMapCamera.clusterPadding,
                    left: MapFlowMapCamera.clusterPadding,
                    bottom: MapFlowMapCamera.clusterPadding,
                    right: MapFlowMapCamera.clusterPadding,
                )
                if let framed = mapView.camera(for: bounds, insets: insets) {
                    let current = mapView.camera
                    if current.zoom > framed.zoom + MapFlowMapCamera.alreadyFramedZoomSlop {
                        steps.append(
                            (
                                GMSCameraUpdate.setTarget(current.target, zoom: framed.zoom),
                                MapFlowMapCamera.zoomOutDuration,
                            ),
                        )
                    }
                } else {
                    steps.append(
                        (
                            GMSCameraUpdate.fit(bounds, withPadding: MapFlowMapCamera.clusterPadding),
                            MapFlowMapCamera.zoomOutDuration,
                        ),
                    )
                }
            }

            let didQueueZoomOut = !steps.isEmpty
            steps.append(
                (
                    GMSCameraUpdate.setTarget(target),
                    MapFlowMapCamera.panDuration,
                ),
            )

            let alreadyAtFocus =
                !didQueueZoomOut
                && bothInView
                && startZoom + MapFlowMapCamera.alreadyFramedZoomSlop >= MapFlowMapCamera.bagFocusZoom
            if !alreadyAtFocus {
                steps.append(
                    (
                        GMSCameraUpdate.setTarget(target, zoom: MapFlowMapCamera.bagFocusZoom),
                        MapFlowMapCamera.zoomInDuration,
                    ),
                )
            }

            runCameraSequence(on: mapView, steps: steps)
            lastFocusedCoordinate = target
        }

        func showAllDevicesOverview(on mapView: GMSMapView, devices: [MapDevice], animated: Bool) {
            let pinned = devices.filter { $0.locationAvailable }
            guard !pinned.isEmpty else { return }
            let cluster = MapFlowCoordinates.clusteredDevices(from: pinned, around: pinned.first)
            if cluster.count == 1, let only = cluster.first {
                let coordinate = MapFlowCoordinates.coordinate(for: only)
                let update = GMSCameraUpdate.setTarget(coordinate, zoom: MapFlowMapCamera.regionalZoom)
                apply(update, on: mapView, animated: animated)
                lastFocusedCoordinate = coordinate
                return
            }
            guard let bounds = MapFlowCoordinates.bounds(for: cluster, around: pinned.first) else { return }
            apply(
                GMSCameraUpdate.fit(bounds, withPadding: MapFlowMapCamera.clusterPadding),
                on: mapView,
                animated: animated,
            )
            lastFocusedCoordinate = nil
        }

        private func areAllVisible(_ devices: [MapDevice], on mapView: GMSMapView) -> Bool {
            guard !devices.isEmpty else { return true }
            let region = mapView.projection.visibleRegion()
            var bounds = GMSCoordinateBounds(coordinate: region.farLeft, coordinate: region.nearRight)
            bounds = bounds.includingCoordinate(region.farRight)
            bounds = bounds.includingCoordinate(region.nearLeft)
            return devices.allSatisfy {
                bounds.contains(MapFlowCoordinates.coordinate(for: $0))
            }
        }

        private func apply(_ update: GMSCameraUpdate, on mapView: GMSMapView, animated: Bool) {
            if animated {
                animateCamera(update, on: mapView, duration: MapFlowMapCamera.panDuration)
            } else {
                mapView.moveCamera(update)
            }
        }

        private func runCameraSequence(on mapView: GMSMapView, steps: [(GMSCameraUpdate, TimeInterval)]) {
            focusSequenceToken += 1
            let token = focusSequenceToken
            guard !steps.isEmpty else { return }

            func perform(from index: Int) {
                guard focusSequenceToken == token, index < steps.count else { return }
                let (update, duration) = steps[index]
                animateCamera(update, on: mapView, duration: duration)
                let next = index + 1
                guard next < steps.count else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + MapFlowMapCamera.pauseBetweenSteps) {
                    [weak mapView, weak self] in
                    guard let mapView, let self, self.focusSequenceToken == token else { return }
                    perform(from: next)
                }
            }
            perform(from: 0)
        }

        private func animateCamera(
            _ update: GMSCameraUpdate,
            on mapView: GMSMapView,
            duration: TimeInterval,
        ) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            mapView.animate(with: update)
            CATransaction.commit()
        }
    }
}

struct MapFlowMapUnavailableView: View {
    var body: some View {
        ZStack {
            Color(red: 220 / 255, green: 228 / 255, blue: 226 / 255)
            Text("Map unavailable")
                .font(.headline)
                .foregroundStyle(MapFlowTheme.onLight.opacity(0.7))
        }
    }
}
