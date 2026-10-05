import BagIdSDK
import Foundation

enum ManagedBleSimulatorMock {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func devices(tagType: AtomicTagType?) -> [DiscoveredEbtBleDevice] {
        let other = tagType == .other
        let identity: EbtTagIdentity = other
            ? EbtTagIdentity.OtherVendor(modelHint: "BagTag Flex")
            : EbtTagIdentity.BagId(model: .bagid2Fm)
        let name = other ? "BagTag Flex" : "BagID 2"
        return [
            DiscoveredEbtBleDevice(
                identity: identity,
                deviceId: "00000000-MOCK-4000-8000-BAGID0000001",
                signalStrength: -42,
                advertisedLocalName: name,
                advertisedUniqueId: "AABBCCDDEEFF0011"
            ),
            DiscoveredEbtBleDevice(
                identity: identity,
                deviceId: "00000000-MOCK-4000-8000-BAGID0000002",
                signalStrength: -61,
                advertisedLocalName: name,
                advertisedUniqueId: "AABBCCDDEEFF0022"
            ),
        ]
    }

    static func successJson(operation: String, device: DiscoveredEbtBleDevice) -> String {
        let dict: [String: Any] = [
            "status": "SUCCESS",
            "operation": operation.uppercased(),
            "data": [
                "mocked": true,
                "deviceId": device.deviceId,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"SUCCESS\",\"operation\":\"\(operation.uppercased())\"}"
        }
        return str
    }
}
