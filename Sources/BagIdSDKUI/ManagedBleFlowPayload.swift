import BagIdSDK
import Foundation

// MARK: - Managed flow envelope (mirrors ManagedFlowEnvelope.kt)

struct ManagedFlowEnvelope {
    struct DeviceSelection {
        let deviceId: String
        let autoSelectTimeoutMs: Double
    }
    let schemaVersion: Int
    let selection: DeviceSelection?
    let data: [String: Any]
}

// MARK: - Parsing

func parseManagedFlowPayload(_ rawJson: String?) -> ManagedFlowEnvelope {
    let root: [String: Any]
    if let raw = rawJson,
       !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
        root = obj
    } else {
        root = [:]
    }

    let schemaVersion = root["schemaVersion"] as? Int ?? 1
    let selection: ManagedFlowEnvelope.DeviceSelection? = {
        guard let sel = root["selection"] as? [String: Any],
              let id = sel["deviceId"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let timeout = sel["autoSelectTimeoutMs"] as? Double ?? 12_000.0
        return .init(
            deviceId: id.trimmingCharacters(in: .whitespacesAndNewlines),
            autoSelectTimeoutMs: max(timeout, 3_000.0)
        )
    }()
    let data = root["data"] as? [String: Any] ?? [:]
    return ManagedFlowEnvelope(schemaVersion: schemaVersion, selection: selection, data: data)
}

extension ManagedFlowEnvelope {
    var targetGuid: String? {
        let trimmed = (data["uniqueDeviceId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 16-hex FICR (`device.uniqueId`) for scan-response manufacturer match.
    var advertisedUniqueId: String? {
        let explicit = (data["advertisedUniqueId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hexSource = explicit.isEmpty ? (targetGuid ?? "") : explicit
        let hex = hexSource.uppercased().filter { $0.isHexDigit }
        return hex.count == 16 ? hex : nil
    }

    var autoSelectTimeoutMs: Double {
        if let selection {
            return selection.autoSelectTimeoutMs
        }
        if let timeout = data["autoSelectTimeoutMs"] as? Double {
            return max(timeout, 3_000.0)
        }
        if let timeout = data["autoSelectTimeoutMs"] as? Int {
            return max(Double(timeout), 3_000.0)
        }
        return 12_000.0
    }
}

enum ManagedFlowPayloadError: Error {
    case missingRequired(String)
}

func buildTransferTagRequest(
    from data: [String: Any],
    deviceId: String,
    uniqueDeviceId: String
) throws -> TransferTagRequest {
    guard let baggageId = idString(data["baggageId"]),
          let journeyId = idString(data["journeyId"]) else {
        throw ManagedFlowPayloadError.missingRequired(
            "TRANSFER payload requires 'baggageId' and 'journeyId' in data."
        )
    }
    let recordLocator = trimmedNonEmpty(data["recordLocator"] as? String)
    let custodyProofSurname = trimmedNonEmpty(data["custodyProofSurname"] as? String)

    let displayTicket: EbtTicket?
    if let obj = data["displayTicket"] as? [String: Any], !obj.isEmpty {
        displayTicket = parseEbtTicket(from: obj)
    } else {
        displayTicket = nil
    }

    let journey: Journey?
    if let obj = data["journey"] as? [String: Any], !obj.isEmpty {
        journey = parseJourney(from: obj)
    } else {
        journey = nil
    }


    let airlineSharingConsent =
        (data["airlineSharingConsent"] as? Bool)
        ?? ((data["displayTicket"] as? [String: Any])?["airlineSharingConsent"] as? Bool)
        ?? false

    return TransferTagRequest(
        deviceId: deviceId,
        uniqueDeviceId: uniqueDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
        baggageId: baggageId,
        journeyId: journeyId,
        recordLocator: recordLocator,
        custodyProofSurname: custodyProofSurname,
        displayTicket: displayTicket,
        journey: journey,
        airlineSharingConsent: airlineSharingConsent,
        journeyData: trimmedNonEmpty(data["journeyData"] as? String)
    )
}

// MARK: - JSON → SDK model parsers

private func parseJourney(from o: [String: Any]) -> Journey? {
    guard let journeyId = idString(o["journeyId"]) else { return nil }
    let recordLocator = trimmedNonEmpty(o["recordLocator"] as? String)
    let passengers = (o["passengers"] as? [[String: Any]] ?? []).compactMap(parseJourneyPassenger)
    let flights = (o["flights"] as? [[String: Any]] ?? []).compactMap(parseFlight)
    let baggage = (o["baggage"] as? [[String: Any]] ?? []).compactMap(parseBaggageRecord)
    let slots = (o["baggageSlots"] as? [[String: Any]] ?? []).compactMap(parseBaggageSlot)
    return Journey(
        journeyId: journeyId,
        recordLocator: recordLocator,
        passengers: passengers,
        flights: flights,
        baggage: baggage,
        baggageSlots: slots,
        scheduledArrival: trimmedNonEmpty(o["scheduledArrival"] as? String),
        totalAllowance: (o["totalAllowance"] as? Int).map { KotlinInt(int: Int32($0)) },
        baggageAllowanceUnit: trimmedNonEmpty(o["baggageAllowanceUnit"] as? String)
    )
}

private func parseJourneyPassenger(from o: [String: Any]) -> Passenger {
    return Passenger(
        passengerId: idString(o["passengerId"]),
        surname: trimmedNonEmpty(o["surname"] as? String),
        givenName: trimmedNonEmpty(o["givenName"] as? String),
        title: trimmedNonEmpty(o["title"] as? String)
    )
}

private func parseFlight(from o: [String: Any]) -> FlightInfo? {
    guard let flightNumber = o["flightNumber"] as? String,
          let dep = o["departureAirport"] as? String,
          let dest = o["destinationAirport"] as? String else { return nil }
    return FlightInfo(
        flightNumber: flightNumber,
        departureAirport: dep,
        destinationAirport: dest,
        departureAt: trimmedNonEmpty(o["departureAt"] as? String)
    )
}

private func parseBaggageRecord(from o: [String: Any]) -> BaggageRecord? {
    guard let baggageId = idString(o["baggageId"]) else { return nil }
    return BaggageRecord(
        baggageId: baggageId,
        baggageTagNumber: trimmedNonEmpty(o["baggageTagNumber"] as? String),
        airline: trimmedNonEmpty(o["airline"] as? String),
        destinationAirport: trimmedNonEmpty(o["destinationAirport"] as? String),
        licensePlate: trimmedNonEmpty(o["licensePlate"] as? String),
        bagTagHumanReadable: trimmedNonEmpty(o["bagTagHumanReadable"] as? String)
    )
}

private func parseBaggageSlot(from o: [String: Any]) -> BaggageSlot? {
    guard let apiSlot = o["apiSlotIndex"] as? Int else { return nil }
    let baggage = (o["baggage"] as? [String: Any]).flatMap(parseBaggageRecord)
    return BaggageSlot(apiSlotIndex: Int32(apiSlot), baggage: baggage)
}

private func parseEbtTicket(from o: [String: Any]) -> EbtTicket? {
    guard let baggageObj = o["baggage"] as? [String: Any],
          let baggageId = idString(baggageObj["baggageId"]) else { return nil }

    let baggage = Baggage(
        baggageId: baggageId,
        priority: baggageObj["priority"] as? Bool ?? false,
        greenstrip: baggageObj["greenstrip"] as? Bool ?? false,
        licenseplate: trimmedNonEmpty(baggageObj["licenseplate"] as? String),
        bagtagHumanReadable: trimmedNonEmpty(baggageObj["bagtagHumanReadable"] as? String)
    )

    let passenger: Passenger_?
    if let pObj = o["passenger"] as? [String: Any] {
        passenger = Passenger_(
            surname: trimmedNonEmpty(pObj["surname"] as? String),
            givenName: trimmedNonEmpty(pObj["givenName"] as? String),
            title: trimmedNonEmpty(pObj["title"] as? String)
        )
    } else {
        passenger = nil
    }


    return EbtTicket(
        recordLocator: trimmedNonEmpty(o["recordLocator"] as? String),
        classOfTravel: trimmedNonEmpty(o["classOfTravel"] as? String),
        destinationFlightNumber: trimmedNonEmpty(o["destinationFlightNumber"] as? String),
        scheduledArrival: trimmedNonEmpty(o["scheduledArrival"] as? String),
        destinationTz: trimmedNonEmpty(o["destinationTz"] as? String),
        destinationAirport: trimmedNonEmpty(o["destinationAirport"] as? String),
        destinationCity: trimmedNonEmpty(o["destinationCity"] as? String),
        firstTransferFlightNumber: trimmedNonEmpty(o["firstTransferFlightNumber"] as? String),
        firstTransferDate: trimmedNonEmpty(o["firstTransferDate"] as? String),
        firstTransferTz: trimmedNonEmpty(o["firstTransferTz"] as? String),
        firstTransferAirport: trimmedNonEmpty(o["firstTransferAirport"] as? String),
        secondTransferFlightNumber: trimmedNonEmpty(o["secondTransferFlightNumber"] as? String),
        secondTransferDate: trimmedNonEmpty(o["secondTransferDate"] as? String),
        secondTransferTz: trimmedNonEmpty(o["secondTransferTz"] as? String),
        secondTransferAirport: trimmedNonEmpty(o["secondTransferAirport"] as? String),
        departureAirport: trimmedNonEmpty(o["departureAirport"] as? String),
        passenger: passenger,
        baggage: baggage,
        baggageId: idString(o["baggageId"])
    )
}

/// An id from the payload: a UUID string in BagID API v2; a number is read as its text.
private func idString(_ value: Any?) -> String? {
    if let s = value as? String { return trimmedNonEmpty(s) }
    if let n = value as? Int { return String(n) }
    return nil
}

private func trimmedNonEmpty(_ s: String?) -> String? {
    guard let s else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

// MARK: - Display title (mirrors ManagedBleFlowDisplayTitle.kt)

func managedBleFlowDisplayTitle(_ operation: String) -> String {
    switch operation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "TRANSFER": return "Transferring Ticket..."
    case "CLEAR": return "Clearing Tag..."
    case "READ_BATTERY": return "Reading Battery..."
    case "READ_FIRMWARE": return "Reading Firmware..."
    case "READ_HUBBLE_ID": return "Reading Hubble ID..."
    case "READ_RFID_TID": return "Reading RFID TID..."
    case "SEND_NAMETAG": return "Sending Image..."
    case "HIDE_TICKET": return "Showing Personal Image..."
    case "RESTORE_TICKET": return "Restoring Bag Tag..."
    default:
        return operation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
    }
}
