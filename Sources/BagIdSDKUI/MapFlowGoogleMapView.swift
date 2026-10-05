import BagIdSDK
import CoreLocation
import GoogleMaps
import QuartzCore
import SwiftUI

private enum MapFlowGms {
    private static var didProvideKey = false

    static func provideAPIKeyOnce(_ key: String) {
        guard !didProvideKey else { return }
        GMSServices.provideAPIKey(key)
        didProvideKey = true
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
    var onSelectDevice: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
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
        context.coordinator.onSelectDevice = onSelectDevice
        context.coordinator.syncMarkers(on: mapView, devices: devices, selectedDeviceId: selectedDeviceId)
        context.coordinator.showAllDevicesOverview(on: mapView, devices: devices, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.mapType = showSatellite ? .hybrid : .normal
        context.coordinator.onSelectDevice = onSelectDevice
        context.coordinator.syncMarkers(on: mapView, devices: devices, selectedDeviceId: selectedDeviceId)
        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            if let id = focusDeviceId, let device = devices.first(where: { $0.id == id }) {
                context.coordinator.focusOnDevice(
                    on: mapView,
                    device: device,
                    allDevices: devices,
                )
            }
        } else if context.coordinator.lastDeviceSignature != deviceCoordinateSignature(devices) {
            context.coordinator.showAllDevicesOverview(on: mapView, devices: devices, animated: true)
        }
        context.coordinator.lastDeviceSignature = deviceCoordinateSignature(devices)
    }

    private func deviceCoordinateSignature(_ devices: [MapDevice]) -> String {
        devices
            .map {
                let c = MapFlowCoordinates.coordinate(for: $0)
                return "\($0.id):\(c.latitude):\(c.longitude)"
            }
            .joined(separator: "|")
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var lastFocusGeneration: Int = -1
        var lastDeviceSignature: String = ""
        var onSelectDevice: ((String) -> Void)?
        private var markers: [String: GMSMarker] = [:]
        private var lastFocusedCoordinate: CLLocationCoordinate2D?
        private var focusSequenceToken = 0

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String {
                onSelectDevice?(id)
            }
            return true
        }

        func syncMarkers(on mapView: GMSMapView, devices: [MapDevice], selectedDeviceId: String?) {
            let ids = Set(devices.map(\.id))
            for (id, marker) in markers where !ids.contains(id) {
                marker.map = nil
                markers.removeValue(forKey: id)
            }
            for device in devices {
                let coordinate = MapFlowCoordinates.coordinate(for: device)
                let isSelected = device.id == selectedDeviceId
                if let marker = markers[device.id] {
                    marker.position = coordinate
                    marker.title = device.displayName
                    marker.icon = MapFlowBagIdMarkerIcon.image(isPrimary: isSelected)
                    marker.groundAnchor = MapFlowBagIdMarkerIcon.groundAnchor
                    marker.zIndex = isSelected ? 10 : 0
                    marker.userData = device.id
                } else {
                    let marker = GMSMarker()
                    marker.position = coordinate
                    marker.title = device.displayName
                    marker.icon = MapFlowBagIdMarkerIcon.image(isPrimary: isSelected)
                    marker.groundAnchor = MapFlowBagIdMarkerIcon.groundAnchor
                    marker.zIndex = isSelected ? 10 : 0
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
            let target = MapFlowCoordinates.coordinate(for: device)
            let cluster = MapFlowCoordinates.clusteredDevices(from: allDevices, around: device)
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
            guard !devices.isEmpty else { return }
            let cluster = MapFlowCoordinates.clusteredDevices(from: devices, around: devices.first)
            if cluster.count == 1, let only = cluster.first {
                let coordinate = MapFlowCoordinates.coordinate(for: only)
                let update = GMSCameraUpdate.setTarget(coordinate, zoom: MapFlowMapCamera.regionalZoom)
                apply(update, on: mapView, animated: animated)
                lastFocusedCoordinate = coordinate
                return
            }
            guard let bounds = MapFlowCoordinates.bounds(for: cluster, around: devices.first) else { return }
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
