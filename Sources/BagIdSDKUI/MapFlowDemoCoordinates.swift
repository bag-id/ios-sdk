import BagIdSDK
import CoreLocation
import GoogleMaps

/// Camera helpers for SHOW_MAP: uses each device's own coordinates.
enum MapFlowCoordinates {
    static func coordinate(for device: MapDevice) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: device.latitude, longitude: device.longitude)
    }

    /// Devices within 2_000 km of `reference` (defaults to the first device). Far outliers are dropped
    /// so the camera can fit the nearby cluster without zooming to a continent.
    static func clusteredDevices(from devices: [MapDevice], around reference: MapDevice? = nil) -> [MapDevice] {
        guard let origin = reference ?? devices.first else { return [] }
        let originCoord = coordinate(for: origin)
        return devices.filter { haversineKm(originCoord, coordinate(for: $0)) <= outlierDistanceKm }
    }

    static func bounds(for devices: [MapDevice], around reference: MapDevice? = nil) -> GMSCoordinateBounds? {
        enclosingBounds(for: clusteredDevices(from: devices, around: reference))
    }

    private static let outlierDistanceKm: Double = 2_000

    private static func enclosingBounds(for devices: [MapDevice]) -> GMSCoordinateBounds? {
        guard let first = devices.first else { return nil }
        let firstCoord = coordinate(for: first)
        var bounds = GMSCoordinateBounds(coordinate: firstCoord, coordinate: firstCoord)
        for device in devices.dropFirst() {
            bounds = bounds.includingCoordinate(coordinate(for: device))
        }
        return bounds
    }

    private static func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let earthKm = 6_371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthKm * asin(min(1, sqrt(h)))
    }
}
